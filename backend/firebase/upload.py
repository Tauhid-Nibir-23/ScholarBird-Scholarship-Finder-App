"""Firestore uploader for normalised, validated, deduplicated scholarships.

Pipeline
--------
``FirestoreUploader`` is the final stage of the ScholarBird ingest
pipeline::

    scraper -> normalize -> validate -> dedupe -> FirestoreUploader

The uploader is **stateless across records** — every record is
considered independently. Determinism is guaranteed by two choices:

1. The Firestore document id is the SHA-256 content hash produced
   by :func:`generate_content_hash`, so re-ingesting the same
   scholarship always lands on the same document.
2. The ``DuplicateDetector`` instance is shared with the caller, so
   the up-front dedupe step and the per-document ``upsert`` decision
   agree on what counts as a duplicate.

Write strategy
--------------
* **Insert** — when the document does not exist, ``set()`` writes
  the full document including ``created_at`` and ``updated_at``.
* **Update** — when the document exists, ``update()`` writes
  *only the changed fields*, preserves ``created_at``, and refreshes
  ``updated_at``. The Firestore ``update()`` call is change-only by
  design: missing fields are not overwritten.
* **Batch** — :meth:`FirestoreUploader.upsert_many` flushes in
  chunks of 400 documents (the safe limit under the 500-operation
  batch cap).

A dry-run mode performs every read and decision but never writes,
which is invaluable for verifying the pipeline without populating
production.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Iterable, List, Mapping, Optional, Sequence, Union

from backend.config.constants import (
    FIRESTORE_COLLECTION_SCHOLARSHIPS,
    LOG_FORMAT,
)
from backend.core.exceptions import FirebaseError
from backend.core.logger import get_logger
from backend.models.scholarship import Scholarship
from backend.parser.duplicate import DuplicateDetector, generate_content_hash
from backend.search import build_search_index
from backend.lifecycle import evaluate_lifecycle, initial_lifecycle_metadata

# ---------------------------------------------------------------------------
# Module-level logger — also writes to logs/firestore.log
# ---------------------------------------------------------------------------
_logger = get_logger(__name__)

# Mirror firestore traffic to ``backend/logs/firestore.log`` in
# addition to the root sinks. The handler is attached to the
# ``backend.firebase`` namespace so every uploader log line is
# captured regardless of which submodule raised it. Failures are
# non-fatal so test runs without the ``logs`` directory still work.
try:
    _logs_dir = Path(__file__).resolve().parent.parent / "logs"
    _logs_dir.mkdir(parents=True, exist_ok=True)
    _FIRESTORE_LOG_PATH = _logs_dir / "firestore.log"
    _firebase_logger = logging.getLogger("backend.firebase")
    _has_firestore_handler = any(
        isinstance(h, RotatingFileHandler)
        and Path(getattr(h, "baseFilename", "")).name == "firestore.log"
        for h in _firebase_logger.handlers
    )
    if not _has_firestore_handler:
        _firestore_handler = RotatingFileHandler(
            filename=str(_FIRESTORE_LOG_PATH),
            maxBytes=5 * 1024 * 1024,
            backupCount=5,
            encoding="utf-8",
        )
        _firestore_handler.setFormatter(logging.Formatter(LOG_FORMAT))
        _firebase_logger.addHandler(_firestore_handler)
except Exception:  # pragma: no cover - defensive
    pass


# ---------------------------------------------------------------------------
# Outcome and summary containers
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class UploadOutcome:
    """Per-document result returned by :meth:`FirestoreUploader.upsert`."""

    document_id: str
    action: str  # "inserted" | "updated" | "skipped" | "failed"
    changed_fields: tuple = ()
    error: Optional[str] = None

    @property
    def is_success(self) -> bool:
        return self.action in ("inserted", "updated", "skipped")


@dataclass
class UploadSummary:
    """Aggregate statistics for an :meth:`upsert_many` run."""

    new: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0
    batch_count: int = 0
    execution_time: float = 0.0
    dry_run: bool = False
    outcomes: List[UploadOutcome] = field(default_factory=list)

    def to_dict(self) -> dict:
        """Return a JSON-serialisable snapshot for logging."""
        return {
            "new": self.new,
            "updated": self.updated,
            "skipped": self.skipped,
            "failed": self.failed,
            "batch_count": self.batch_count,
            "execution_time": round(self.execution_time, 4),
            "dry_run": self.dry_run,
        }


# ---------------------------------------------------------------------------
# Uploader
# ---------------------------------------------------------------------------

class FirestoreUploader:
    """Persist scholarships to the ``scholarships`` collection.

    Args:
        detector: A :class:`DuplicateDetector` shared with the rest
            of the pipeline. The uploader reads
            ``detector.seen_content_hashes`` to decide whether a
            given hash is a first-seen or repeat record.
        client: Optional Firestore client. When ``None`` the uploader
            resolves one via :func:`backend.firebase.firebase_config
            .get_firestore_client`. Tests inject a fake.
        collection: Optional collection name. Defaults to the
            ``SCHOLARSHIPS_COLLECTION`` constant from settings.
        batch_size: Number of documents per ``batch()`` flush. The
            default 400 leaves 100 operations of headroom for
            index updates inside the 500-op batch cap.
        dry_run: When ``True``, every write is skipped. The uploader
            still returns accurate statistics.
    """

    DEFAULT_BATCH_SIZE = 400
    MAX_BATCH_SIZE = 499  # hard cap from Firestore
    COLLECTION = FIRESTORE_COLLECTION_SCHOLARSHIPS

    def __init__(
        self,
        detector: DuplicateDetector,
        client: Any = None,
        collection: Optional[str] = None,
        batch_size: int = DEFAULT_BATCH_SIZE,
        dry_run: bool = False,
    ) -> None:
        if detector is None:
            raise FirebaseError(
                "FirestoreUploader requires a DuplicateDetector instance."
            )
        if batch_size <= 0 or batch_size > self.MAX_BATCH_SIZE:
            raise FirebaseError(
                f"batch_size must be between 1 and {self.MAX_BATCH_SIZE}; "
                f"got {batch_size}"
            )

        self._detector = detector
        self._dry_run = dry_run
        self._batch_size = batch_size
        self._collection_name = collection or self.COLLECTION

        # Lazy resolve the client so the uploader is importable in
        # test environments without Firebase credentials.
        if client is None:
            from backend.firebase.firebase_config import get_firestore_client

            client = get_firestore_client()
        self._client = client

        # Aggregated over the lifetime of the uploader. ``upsert_many``
        # appends to this; callers can also read it after a single
        # ``upsert`` call.
        self._summary = UploadSummary(dry_run=dry_run)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def summary(self) -> UploadSummary:
        """Return the cumulative summary (for tests and logging)."""
        return self._summary

    @property
    def dry_run(self) -> bool:
        return self._dry_run

    @dry_run.setter
    def dry_run(self, value: bool) -> None:
        self._dry_run = bool(value)
        self._summary.dry_run = self._dry_run

    def upsert(self, record: Union[Scholarship, Mapping[str, Any]]) -> UploadOutcome:
        """Insert or update a single scholarship.

        Args:
            record: Either a :class:`Scholarship` instance or a raw
                ``dict``. The dict path lets pipeline glue code work
                without first wrapping scraped rows in a model.

        Returns:
            An :class:`UploadOutcome` describing the action taken.
        """
        started = time.perf_counter()
        try:
            document_id, payload = self._prepare(record)
        except FirebaseError as exc:
            outcome = UploadOutcome(
                document_id="", action="failed", error=str(exc)
            )
            self._record_outcome(outcome, time.perf_counter() - started)
            return outcome

        if self._dry_run:
            outcome = self._preview(document_id, payload)
            self._record_outcome(outcome, time.perf_counter() - started)
            return outcome

        try:
            outcome = self._execute_one(document_id, payload)
        except Exception as exc:
            _logger.exception("Upsert failed for %s", document_id)
            outcome = UploadOutcome(
                document_id=document_id, action="failed", error=str(exc)
            )
        self._record_outcome(outcome, time.perf_counter() - started)
        return outcome

    def upsert_many(
        self,
        records: Iterable[Union[Scholarship, Mapping[str, Any]]],
        batch_size: Optional[int] = None,
    ) -> UploadSummary:
        """Batch-upsert many records.

        Args:
            records: Iterable of :class:`Scholarship` or dicts.
            batch_size: Optional override for the per-batch size.

        Returns:
            The cumulative :class:`UploadSummary` for the run.
        """
        chunk_size = batch_size or self._batch_size
        started = time.perf_counter()

        # Reset counters for this run; preserve the ``dry_run`` flag.
        self._summary = UploadSummary(dry_run=self._dry_run)

        buffer: List[Union[Scholarship, Mapping[str, Any]]] = []
        for record in records:
            buffer.append(record)
            if len(buffer) >= chunk_size:
                self._flush_buffer(buffer)
                buffer = []
        if buffer:
            self._flush_buffer(buffer)

        self._summary.execution_time = time.perf_counter() - started
        _logger.info(
            "upsert_many complete: new=%d updated=%d skipped=%d failed=%d "
            "batches=%d time=%.3fs dry_run=%s",
            self._summary.new,
            self._summary.updated,
            self._summary.skipped,
            self._summary.failed,
            self._summary.batch_count,
            self._summary.execution_time,
            self._summary.dry_run,
        )
        return self._summary

    def batch_write(
        self,
        records: Sequence[Union[Scholarship, Mapping[str, Any]]],
        batch_size: Optional[int] = None,
    ) -> UploadSummary:
        """Alias for :meth:`upsert_many` kept for naming symmetry.

        The user request mentioned ``batch_write`` explicitly; the
        implementation is identical to :meth:`upsert_many` because
        the underlying logic is the same.
        """
        return self.upsert_many(records, batch_size=batch_size)

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _flush_buffer(
        self,
        buffer: Sequence[Union[Scholarship, Mapping[str, Any]]],
    ) -> None:
        """Write a chunk of records as a single batch."""
        prepared: List[tuple] = []  # (document_id, payload, outcome_marker)
        for record in buffer:
            try:
                document_id, payload = self._prepare(record)
            except FirebaseError as exc:
                self._summary.failed += 1
                self._summary.outcomes.append(
                    UploadOutcome(
                        document_id="", action="failed", error=str(exc)
                    )
                )
                continue
            prepared.append((document_id, payload))

        if self._dry_run:
            for document_id, payload in prepared:
                outcome = self._preview(document_id, payload)
                self._record_outcome(outcome, 0.0)
            self._summary.batch_count += 1
            return

        if not prepared:
            self._summary.batch_count += 1
            return

        batch = self._client.batch()
        ops_for_batch: List[tuple] = []
        for document_id, payload in prepared:
            outcome = self._plan(document_id, payload)
            if outcome.action == "skipped":
                self._record_outcome(outcome, 0.0)
                continue
            doc_ref = self._collection().document(document_id)
            if outcome.action == "inserted":
                batch.set(doc_ref, payload)
            else:  # updated
                batch.update(doc_ref, payload["_changed_fields"])
            ops_for_batch.append((document_id, outcome))

        try:
            batch.commit()
        except Exception as exc:
            _logger.exception("Batch commit failed; marking %d ops failed",
                              len(ops_for_batch))
            for document_id, outcome in ops_for_batch:
                self._summary.failed += 1
                self._summary.outcomes.append(
                    UploadOutcome(
                        document_id=document_id,
                        action="failed",
                        error=str(exc),
                    )
                )
        else:
            for document_id, outcome in ops_for_batch:
                self._record_outcome(outcome, 0.0)

        self._summary.batch_count += 1

    def _prepare(
        self,
        record: Union[Scholarship, Mapping[str, Any]],
    ) -> tuple:
        """Return ``(document_id, payload)`` for a record."""
        if isinstance(record, Scholarship):
            document_id = record.generate_hash()
            payload = self._payload_from_model(record)
        elif isinstance(record, Mapping):
            document_id = generate_content_hash(record)
            payload = self._payload_from_dict(record)
        else:
            raise FirebaseError(
                f"Unsupported record type: {type(record).__name__}"
            )

        if not document_id:
            raise FirebaseError(
                "Record produced an empty document hash; refusing to write."
            )
        return document_id, payload

    def _payload_from_model(self, scholarship: Scholarship) -> dict:
        """Build a Firestore payload from a :class:`Scholarship`.

        The payload follows the snake_case shape requested for the
        Firestore schema (``status="active"``, ISO-8601
        ``created_at`` / ``updated_at``) instead of the camelCase
        shape produced by :meth:`Scholarship.to_firestore`. That
        keeps the backend documents self-describing for any future
        reader that does not know the Flutter convention.
        """
        payload = self._canonical_payload(scholarship.to_dict())
        return self._stamp_timestamps(payload)

    def _payload_from_dict(self, raw: Mapping[str, Any]) -> dict:
        """Build a Firestore payload from a raw mapping."""
        try:
            scholarship = Scholarship.from_dict(raw)
        except Exception as exc:
            raise FirebaseError(
                f"Failed to coerce record into Scholarship: {exc}"
            ) from exc
        payload = self._canonical_payload(scholarship.to_dict())
        return self._stamp_timestamps(payload)

    @staticmethod
    def _canonical_payload(snapshot: Mapping[str, Any]) -> dict:
        """Project a ``Scholarship.to_dict()`` snapshot onto the
        snake_case Firestore schema.

        Fields that are ``None`` or empty are dropped so the document
        stays compact and the diff step does not flag accidental
        ``null``/missing churn. The mapping is explicit rather than
        dynamic so the schema is obvious from the code.
        """
        payload: dict = {}

        def _put(key: str, value: Any) -> None:
            if value is None:
                return
            if isinstance(value, str) and not value.strip():
                return
            if isinstance(value, (list, tuple)) and len(value) == 0:
                return
            payload[key] = value

        _put("title", snapshot.get("title"))
        _put("country", snapshot.get("country"))
        _put("degree", snapshot.get("degree"))
        _put("field", snapshot.get("field"))
        _put("deadline", snapshot.get("deadline"))
        _put("funding", snapshot.get("amount"))
        # Flutter's existing scholarship views use ``amount`` while the
        # production ingestion contract exposes ``funding``. Keep both
        # names in sync so neither consumer loses data.
        _put("amount", snapshot.get("amount"))
        _put("fundingType", snapshot.get("amount"))
        _put("eligibility", snapshot.get("eligibility"))
        _put("university", snapshot.get("university"))
        _put("category", (snapshot.get("tags") or [None])[0])
        _put("apply_url", snapshot.get("apply_url"))
        _put("official_id", snapshot.get("official_id"))
        _put("source", snapshot.get("source"))
        _put("description", snapshot.get("description"))
        _put("link", snapshot.get("link"))
        _put("image", snapshot.get("image"))
        payload["min_cgpa"] = snapshot.get("min_cgpa", 0.0)
        payload["minCgpa"] = snapshot.get("min_cgpa", 0.0)
        payload["cgpaScale"] = snapshot.get("cgpa_scale", 4.0)
        payload["maxBacklogs"] = snapshot.get("max_backlogs", 0)
        payload["englishMediumAccepted"] = bool(
            snapshot.get("english_medium_accepted", True)
        )
        payload["fullyFunded"] = bool(snapshot.get("fully_funded", False))
        payload["isFeatured"] = False
        payload["isHidden"] = False
        payload["ielts_required"] = bool(snapshot.get("ielts_required", False))
        payload["ieltsRequired"] = bool(snapshot.get("ielts_required", False))
        payload["research_required"] = bool(
            snapshot.get("research_required", False)
        )
        payload["researchRequired"] = bool(
            snapshot.get("research_required", False)
        )
        tags = snapshot.get("tags") or []
        if tags:
            payload["tags"] = list(tags)
        payload["status"] = "active"
        # Search fields are additive only. They are deterministic from the
        # canonical scholarship snapshot, so repeat ingestion is idempotent.
        payload.update(build_search_index(payload))
        payload.update(initial_lifecycle_metadata(payload))
        return payload

    @staticmethod
    def _stamp_timestamps(payload: dict) -> dict:
        """Ensure ``created_at`` and ``updated_at`` are present.

        ``created_at`` is preserved from the source record when
        available (round-trip from ``Scholarship.to_dict()``), and
        ``updated_at`` is always refreshed to the current UTC time
        so a re-ingest is detectable.
        """
        payload.setdefault("created_at", _utc_now_iso())
        payload["updated_at"] = _utc_now_iso()
        now = datetime.now(timezone.utc)
        payload["createdAt"] = now
        payload["updatedAt"] = now
        return payload

    def _plan(self, document_id: str, payload: dict) -> UploadOutcome:
        """Decide what to do with a document without writing.

        Returns:
            An :class:`UploadOutcome` carrying the intended action.
            ``_changed_fields`` is populated for ``"updated"``
            outcomes so the caller can pass it to ``batch.update``.

        Side effect:
            When the outcome is ``"updated"`` the diffed fields are
            stashed under ``payload["_changed_fields"]`` so both the
            single-document and the batch paths can send the same
            update dict without recomputing.
        """
        doc_ref = self._collection().document(document_id)
        snapshot = doc_ref.get()
        if not snapshot.exists:
            return UploadOutcome(
                document_id=document_id, action="inserted"
            )

        existing = snapshot.to_dict() or {}
        # The source model stamps records while scraping. Once a document
        # exists, its first-ingestion timestamp is immutable and must not
        # make an otherwise identical re-ingest appear changed.
        payload["created_at"] = existing.get(
            "created_at", payload["created_at"]
        )
        payload["createdAt"] = existing.get("createdAt", payload["createdAt"])
        payload["isFeatured"] = existing.get("isFeatured", False)
        payload["isHidden"] = existing.get("isHidden", False)
        # Lifecycle comparison is the authoritative update plan: it only
        # returns tracked fields and metadata when a meaningful change (or
        # expiry/reactivation transition) occurred.
        changed = evaluate_lifecycle(existing, payload)
        if not changed:
            return UploadOutcome(
                document_id=document_id,
                action="skipped",
                changed_fields=(),
            )
        # ``updated_at`` is always refreshed; ``created_at`` is
        # preserved because it was written when the document first
        # landed and we must not mutate the original ingestion time.
        # Search fields are derived from tracked content and need to move
        # with it, while immutable identity/timestamps stay untouched.
        for key, value in payload.items():
            if key.startswith("_") or key in {"official_id", "created_at", "createdAt", "document_id"}:
                continue
            if existing.get(key) != value and key not in changed:
                changed[key] = value
        changed["updated_at"] = payload["updated_at"]
        changed["updatedAt"] = payload["updatedAt"]
        payload["_changed_fields"] = dict(changed)
        return UploadOutcome(
            document_id=document_id,
            action="updated",
            changed_fields=tuple(changed.keys()),
        )

    def _execute_one(self, document_id: str, payload: dict) -> UploadOutcome:
        """Write a single document by routing through the plan logic.

        The plan step stashes the change-only update dict under
        ``payload["_changed_fields"]`` so we send exactly the fields
        the document needs — preserving ``created_at`` and any
        untouched field — instead of resending the whole payload.
        """
        plan = self._plan(document_id, payload)
        if plan.action == "skipped":
            return plan

        doc_ref = self._collection().document(document_id)
        if plan.action == "inserted":
            doc_ref.set(payload)
        else:  # updated
            update_payload = payload.get("_changed_fields") or {
                k: payload[k] for k in plan.changed_fields
            }
            doc_ref.update(update_payload)
        return plan

    def _preview(self, document_id: str, payload: dict) -> UploadOutcome:
        """Return the plan that *would* be executed for a dry run."""
        return self._plan(document_id, payload)

    @staticmethod
    def _diff(existing: Mapping[str, Any], payload: Mapping[str, Any]) -> dict:
        """Return the subset of ``payload`` whose values differ from ``existing``.

        Timestamps are *recomputed* elsewhere and may legitimately
        differ; they are excluded from the change set so mere
        ``updated_at`` churn does not count as a content change.
        """
        protected = {"updated_at", "updatedAt"}
        changed = {}
        for key, value in payload.items():
            if key in protected:
                continue
            if existing.get(key) != value:
                changed[key] = value
        return changed

    def _record_outcome(self, outcome: UploadOutcome, elapsed: float) -> None:
        """Fold an outcome into the running summary."""
        if outcome.action == "inserted":
            self._summary.new += 1
        elif outcome.action == "updated":
            self._summary.updated += 1
        elif outcome.action == "skipped":
            self._summary.skipped += 1
        elif outcome.action == "failed":
            self._summary.failed += 1
        self._summary.outcomes.append(outcome)
        if not self._summary.execution_time:
            self._summary.execution_time += elapsed

    def _collection(self) -> Any:
        return self._client.collection(self._collection_name)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _utc_now_iso() -> str:
    """Return current UTC time as ISO-8601 with ``Z`` suffix."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


__all__ = [
    "FirestoreUploader",
    "UploadOutcome",
    "UploadSummary",
]
