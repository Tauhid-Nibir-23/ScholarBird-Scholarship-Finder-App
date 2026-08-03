"""Smoke tests for the Firestore uploader.

The harness mirrors :mod:`backend.tests.test_duplicate` — every
section banner prints a ``PASS`` / ``FAIL`` line for each check and
the script returns ``0`` only when every check passes. The script is
runnable as ``python backend/tests/test_firestore.py``.

The real Firebase SDK is **never invoked**: a hand-rolled fake
``FakeFirestoreClient`` is injected into :class:`FirestoreUploader`
so the test suite runs offline. Production wiring exercises the
real client through :func:`backend.firebase.firebase_config
.get_firestore_client`.

Sections covered (30+ checks):

* upload payload shape (canonical snake_case schema)
* document id = SHA-256 content hash
* insert path (``upsert`` against an empty collection)
* update path (``update`` is change-only, preserves ``created_at``,
  refreshes ``updated_at``)
* skipped path (no diff between existing and incoming)
* dry-run mode (no writes, statistics still accurate)
* batch / chunking (400-doc batches, 10k records fit)
* statistics dataclass (``UploadSummary.to_dict``)
* error paths (bad client, batch failure, prepare failure)
* re-ingest idempotency (second run reports ``skipped``)
"""

from __future__ import annotations

import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.core.exceptions import FirebaseError  # noqa: E402
from backend.firebase.upload import (  # noqa: E402
    FirestoreUploader,
    UploadOutcome,
    UploadSummary,
)
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.parser.duplicate import (  # noqa: E402
    DuplicateDetector,
    generate_content_hash,
)

_PASS: int = 0
_FAIL: int = 0
_FAILURES: List[str] = []


def banner(title: str) -> None:
    """Print a section heading."""
    print()
    print(title)
    print("-" * len(title))


def expect(label: str, actual: object, expected: object) -> None:
    """Compare ``actual`` against ``expected`` and tally the result."""
    global _PASS, _FAIL
    if actual == expected:
        print(f"  PASS  {label}")
        _PASS += 1
    else:
        print(f"  FAIL  {label}  expected={expected!r}  actual={actual!r}")
        _FAIL += 1
        _FAILURES.append(
            f"{label}: expected={expected!r} actual={actual!r}"
        )


def expect_true(label: str, actual: object) -> None:
    """Tally a boolean expectation."""
    expect(label, bool(actual), True)


def expect_false(label: str, actual: object) -> None:
    """Tally a boolean expectation."""
    expect(label, bool(actual), False)


def expect_raises(label: str, exc_type: type, func, *args, **kwargs) -> None:
    """Tally that calling ``func`` raises ``exc_type``."""
    global _PASS, _FAIL
    try:
        func(*args, **kwargs)
    except exc_type:
        print(f"  PASS  {label}")
        _PASS += 1
        return
    except Exception as exc:  # noqa: BLE001
        print(f"  FAIL  {label}  raised {type(exc).__name__} not {exc_type.__name__}")
        _FAIL += 1
        _FAILURES.append(f"{label}: raised wrong exception {exc!r}")
        return
    print(f"  FAIL  {label}  no exception raised")
    _FAIL += 1
    _FAILURES.append(f"{label}: no exception raised")


# ---------------------------------------------------------------------------
# Fake Firestore client
# ---------------------------------------------------------------------------

class FakeDocumentSnapshot:
    """In-memory stand-in for ``google.cloud.firestore.DocumentSnapshot``."""

    def __init__(self, exists: bool, data: Optional[Dict[str, Any]] = None) -> None:
        self._exists = exists
        self._data = data or {}

    @property
    def exists(self) -> bool:
        return self._exists

    def to_dict(self) -> Dict[str, Any]:
        return dict(self._data)


class FakeDocumentRef:
    """Mimics the subset of ``DocumentReference`` used by the uploader."""

    def __init__(self, collection: "FakeCollection", document_id: str) -> None:
        self._collection = collection
        self._id = document_id

    @property
    def id(self) -> str:
        return self._id

    def get(self) -> FakeDocumentSnapshot:
        record = self._collection.docs.get(self._id)
        if record is None:
            return FakeDocumentSnapshot(exists=False)
        return FakeDocumentSnapshot(exists=True, data=record)

    def set(self, data: Dict[str, Any]) -> None:
        self._collection.writes.append(("set", self._id, dict(data)))
        existing = self._collection.docs.get(self._id, {})
        existing.update(data)
        self._collection.docs[self._id] = existing

    def update(self, data: Dict[str, Any]) -> None:
        self._collection.writes.append(("update", self._id, dict(data)))
        existing = self._collection.docs.get(self._id)
        if existing is None:
            raise RuntimeError(
                f"Cannot update missing document {self._id}"
            )
        existing.update(data)
        self._collection.docs[self._id] = existing

    @property
    def _coll_name(self) -> str:
        # Helper used by ``FakeBatch`` to route writes back to the
        # correct collection when the batch spans multiple.
        return self._collection.name


class FakeBatch:
    """Collects ``set`` / ``update`` ops and commits them atomically.

    The batch is bound to the :class:`FakeFirestoreClient` so writes
    always land in the correct collection, mirroring how the real
    Firestore admin SDK lets a single batch span multiple
    collections.
    """

    def __init__(self, client: "FakeFirestoreClient") -> None:
        self._client = client
        self._ops: List[Tuple[str, str, Dict[str, Any]]] = []

    def set(self, ref: FakeDocumentRef, data: Dict[str, Any]) -> None:
        self._ops.append((ref._coll_name, "set", ref.id, dict(data)))

    def update(self, ref: FakeDocumentRef, data: Dict[str, Any]) -> None:
        self._ops.append((ref._coll_name, "update", ref.id, dict(data)))

    def commit(self) -> None:
        for coll_name, op, doc_id, payload in self._ops:
            collection = self._client.collection(coll_name)
            if collection.fail_next_commit:
                collection.fail_next_commit = False
                raise RuntimeError("simulated batch failure")
            existing = collection.docs.get(doc_id, {})
            existing.update(payload)
            collection.docs[doc_id] = existing
            collection.writes.append((op, doc_id, dict(payload)))


class FakeCollection:
    """Mimics the subset of ``CollectionReference`` used by the uploader."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.docs: Dict[str, Dict[str, Any]] = {}
        self.writes: List[Tuple[str, str, Dict[str, Any]]] = []
        self.fail_next_commit = False

    def document(self, doc_id: str) -> FakeDocumentRef:
        return FakeDocumentRef(self, doc_id)

    def batch(self) -> FakeBatch:
        return FakeBatch(self)


class FakeFirestoreClient:
    """Minimal in-memory replacement for ``firestore.Client``."""

    def __init__(self) -> None:
        self._collections: Dict[str, FakeCollection] = {}

    def collection(self, name: str) -> FakeCollection:
        return self._collections.setdefault(name, FakeCollection(name))

    def batch(self) -> FakeBatch:
        # Real Firestore ``client.batch()`` returns a fresh batch that
        # is *unbound* to a collection; ops reference documents via
        # their :class:`CollectionReference`. The fake mirrors that by
        # routing each ``set`` / ``update`` op back to the right
        # ``FakeCollection`` at commit time, so a single batch can
        # span collections without losing writes.
        return FakeBatch(self)


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def baseline_record(**overrides: Any) -> Dict[str, Any]:
    """Return a known-good scholarship dict, optionally tweaked."""
    base = {
        "title": "Fulbright Foreign Student Programme",
        "country": "United States",
        "degree": "Masters",
        "field": "Engineering",
        "deadline": "2026-10-15",
        "amount": "Fully Funded",
        "description": "Description for the Fulbright programme.",
        "link": "https://example.com/fulbright",
        "university": "Various US universities",
        "source": "test",
        "official_id": "ft-001",
        "apply_url": "https://apply.example.com/fulbright",
        "tags": ["engineering"],
        "eligibility": "International students",
        "created_at": datetime(2024, 1, 1, 12, 0, 0).isoformat(),
        "updated_at": datetime(2024, 1, 1, 12, 0, 0).isoformat(),
    }
    base.update(overrides)
    return base


def baseline_scholarship(**overrides: Any) -> Scholarship:
    """Return a Scholarship built from :func:`baseline_record`."""
    data = baseline_record(**overrides)
    return Scholarship.from_dict(data)


def make_uploader(
    client: FakeFirestoreClient,
    detector: DuplicateDetector,
    dry_run: bool = False,
    batch_size: int = 400,
) -> FirestoreUploader:
    """Build a :class:`FirestoreUploader` wired to fakes."""
    return FirestoreUploader(
        detector=detector,
        client=client,
        collection="scholarships",
        batch_size=batch_size,
        dry_run=dry_run,
    )


# ---------------------------------------------------------------------------
# Section 1 — payload shape
# ---------------------------------------------------------------------------

def test_payload_shape() -> None:
    banner("Payload shape")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    scholarship = baseline_scholarship()
    outcome = uploader.upsert(scholarship)

    expect_true("upsert returned outcome", isinstance(outcome, UploadOutcome))
    expect("first upsert inserts", outcome.action, "inserted")

    collection = client.collection("scholarships")
    expect("collection has 1 doc", len(collection.docs), 1)

    written = next(iter(collection.docs.values()))
    expect("status is active", written.get("status"), "active")
    expect_true("title carried", bool(written.get("title")))
    expect_true("country carried", bool(written.get("country")))
    expect_true("degree carried", bool(written.get("degree")))
    expect_true("deadline carried", bool(written.get("deadline")))
    expect_true("funding carried", bool(written.get("funding")))
    expect_true("eligibility carried", bool(written.get("eligibility")))
    expect_true("university carried", bool(written.get("university")))
    expect_true("apply_url carried", bool(written.get("apply_url")))
    expect_true("official_id carried", bool(written.get("official_id")))
    expect_true("source carried", bool(written.get("source")))
    expect_true("created_at is ISO-8601", isinstance(written.get("created_at"), str))
    expect_true("updated_at is ISO-8601", isinstance(written.get("updated_at"), str))


# ---------------------------------------------------------------------------
# Section 2 — document id = content hash
# ---------------------------------------------------------------------------

def test_document_id_is_content_hash() -> None:
    banner("Document id = content hash")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    record = baseline_record()
    expected_hash = generate_content_hash(record)
    expect("hash is 64 chars", len(expected_hash), 64)

    uploader.upsert(record)
    collection = client.collection("scholarships")
    doc_ids = list(collection.docs.keys())
    expect("exactly one doc written", len(doc_ids), 1)
    expect("document id == content hash", doc_ids[0], expected_hash)

    # Preserve the ingestion schema while also writing Flutter's
    # Firestore Timestamp-compatible camelCase fields.
    payload = collection.docs[doc_ids[0]]
    expect_true("payload includes Flutter createdAt", "createdAt" in payload)
    expect_true("payload includes Flutter updatedAt", "updatedAt" in payload)
    expect_false("payload uses snake_case apply_url", "applyUrl" in payload)
    expect_false("payload uses snake_case official_id", "officialId" in payload)


# ---------------------------------------------------------------------------
# Section 3 — update path is change-only
# ---------------------------------------------------------------------------

def test_update_path_is_change_only() -> None:
    banner("Update path is change-only")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    original = baseline_scholarship()
    uploader.upsert(original)
    collection = client.collection("scholarships")
    doc_id = next(iter(collection.docs.keys()))
    created_at_before = collection.docs[doc_id]["created_at"]

    # Touch one field; everything else should be left alone.
    # ``updated_at`` is stamped at second precision (ISO-8601), so
    # we sleep just past one whole second to guarantee the new
    # timestamp differs from the original.
    time.sleep(1.05)
    changed = baseline_scholarship(amount="Fully Funded (revised)")
    outcome = uploader.upsert(changed)
    expect("second upsert updates", outcome.action, "updated")
    expect_true("changed_fields is non-empty",
                len(outcome.changed_fields) > 0)
    expect_true("funding present in changed_fields",
                "funding" in outcome.changed_fields)

    after = collection.docs[doc_id]
    expect("funding refreshed", after["funding"], "Fully Funded (revised)")
    expect("created_at preserved on update", after["created_at"], created_at_before)
    expect_true("updated_at refreshed on update",
                after["updated_at"] != created_at_before)
    expect_true("updated_at is strictly newer",
                after["updated_at"] > created_at_before)

    # No spurious writes for untouched fields.
    expect("title untouched", after["title"], original.title)
    expect("country untouched", after["country"], original.country)


# ---------------------------------------------------------------------------
# Section 4 — skip when no diff
# ---------------------------------------------------------------------------

def test_skip_when_no_diff() -> None:
    banner("Skip when no diff")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    uploader.upsert(baseline_record())
    second = uploader.upsert(baseline_record())

    expect("second upsert skipped", second.action, "skipped")
    expect("summary skipped count is 1",
           uploader.summary.skipped, 1)
    expect("summary new count is 1", uploader.summary.new, 1)
    expect("summary updated count is 0",
           uploader.summary.updated, 0)

    collection = client.collection("scholarships")
    # Only the original set was committed; the skip wrote nothing.
    expect("no extra write", len(collection.writes), 1)


# ---------------------------------------------------------------------------
# Section 5 — dry-run mode
# ---------------------------------------------------------------------------

def test_dry_run_mode() -> None:
    banner("Dry-run mode")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector, dry_run=True)

    summary = uploader.upsert_many([
        baseline_record(official_id="dry-1"),
        baseline_record(official_id="dry-2", title="Other scholarship"),
        baseline_record(official_id="dry-3", title="Third scholarship"),
    ])

    collection = client.collection("scholarships")
    expect("dry-run wrote nothing", len(collection.docs), 0)
    expect("dry-run summary reports 3 new",
           (summary.new, summary.skipped, summary.failed),
           (3, 0, 0))
    expect_true("summary marks dry_run", summary.dry_run)


# ---------------------------------------------------------------------------
# Section 6 — batch / chunking
# ---------------------------------------------------------------------------

def test_batch_chunking() -> None:
    banner("Batch / chunking")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector, batch_size=2)

    records = [
        baseline_record(official_id=f"b-{i}", title=f"Batch item {i}")
        for i in range(5)
    ]
    summary = uploader.upsert_many(records)

    collection = client.collection("scholarships")
    expect("5 docs persisted", len(collection.docs), 5)
    expect("batch_count = ceil(5/2) = 3", summary.batch_count, 3)
    expect("summary new count", summary.new, 5)


# ---------------------------------------------------------------------------
# Section 7 — statistics dataclass
# ---------------------------------------------------------------------------

def test_statistics_dataclass() -> None:
    banner("Statistics dataclass")

    summary = UploadSummary(
        new=3, updated=2, skipped=1, failed=0,
        batch_count=2, execution_time=1.234, dry_run=False,
    )
    snap = summary.to_dict()
    expect("to_dict new", snap["new"], 3)
    expect("to_dict updated", snap["updated"], 2)
    expect("to_dict skipped", snap["skipped"], 1)
    expect("to_dict failed", snap["failed"], 0)
    expect("to_dict batch_count", snap["batch_count"], 2)
    expect("to_dict execution_time", snap["execution_time"], 1.234)
    expect("to_dict dry_run", snap["dry_run"], False)
    expect_true("execution_time is rounded",
                summary.to_dict()["execution_time"] == 1.234)


# ---------------------------------------------------------------------------
# Section 8 — error paths
# ---------------------------------------------------------------------------

def test_error_paths() -> None:
    banner("Error paths")

    # Constructor rejects None detector.
    expect_raises(
        "None detector raises FirebaseError",
        FirebaseError,
        FirestoreUploader,
        detector=None,
        client=FakeFirestoreClient(),
    )

    # Constructor rejects batch_size > 499.
    expect_raises(
        "batch_size > 499 raises FirebaseError",
        FirebaseError,
        FirestoreUploader,
        detector=DuplicateDetector(),
        client=FakeFirestoreClient(),
        batch_size=500,
    )

    # Batch commit failure marks the affected docs as failed.
    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    collection = client.collection("scholarships")
    collection.fail_next_commit = True
    uploader = make_uploader(client, detector)
    summary = uploader.upsert_many([
        baseline_record(official_id="err-1"),
        baseline_record(official_id="err-2"),
    ])
    expect("failed count includes failed batch",
           summary.failed, 2)
    expect_true("no docs persisted after batch failure",
                len(collection.docs) == 0)

    # Unsupported record type — the single-upsert path wraps it in
    # a failed outcome rather than raising out of the call site.
    detector2 = DuplicateDetector()
    client2 = FakeFirestoreClient()
    uploader2 = make_uploader(client2, detector2)
    bad = uploader2.upsert("not a scholarship")
    expect("unsupported record marked failed", bad.action, "failed")
    expect_true("failure outcome carries error message", bool(bad.error))


# ---------------------------------------------------------------------------
# Section 9 — re-ingest idempotency
# ---------------------------------------------------------------------------

def test_reingest_idempotency() -> None:
    banner("Re-ingest idempotency")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    records = [baseline_record(official_id=f"re-{i}", title=f"Re-ingest {i}")
               for i in range(3)]
    first = uploader.upsert_many(records)
    expect("first run inserts all", first.new, 3)

    second = uploader.upsert_many(records)
    expect("second run inserts nothing", second.new, 0)
    expect("second run skips everything",
           second.skipped, 3)
    expect("second run updated nothing",
           second.updated, 0)


# ---------------------------------------------------------------------------
# Section 10 — performance gate (10k records)
# ---------------------------------------------------------------------------

def test_performance_10k() -> None:
    banner("Performance gate (10k records)")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector, batch_size=400)

    started = time.perf_counter()
    def gen():
        for i in range(10_000):
            yield baseline_record(
                official_id=f"perf-{i}",
                title=f"Perf item {i}",
            )

    summary = uploader.upsert_many(gen())
    elapsed = time.perf_counter() - started

    collection = client.collection("scholarships")
    expect("10k docs persisted", len(collection.docs), 10_000)
    expect("summary new count", summary.new, 10_000)
    # 10k / 400 = 25 batches exactly.
    expect("batch_count = 25", summary.batch_count, 25)
    expect_true("10k run under 30s", elapsed < 30.0,
                )
    print(f"    (10k run took {elapsed:.2f}s)")


# ---------------------------------------------------------------------------
# Section 11 — uploaded fields include category from first tag
# ---------------------------------------------------------------------------

def test_category_from_tags() -> None:
    banner("Category from tags")

    detector = DuplicateDetector()
    client = FakeFirestoreClient()
    uploader = make_uploader(client, detector)

    scholarship = baseline_scholarship(tags=["Engineering", "STEM"])
    uploader.upsert(scholarship)
    doc = next(iter(client.collection("scholarships").docs.values()))
    expect("category pulled from first tag",
           doc["category"], "Engineering")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    """Run every section and return the process exit code."""
    test_payload_shape()
    test_document_id_is_content_hash()
    test_update_path_is_change_only()
    test_skip_when_no_diff()
    test_dry_run_mode()
    test_batch_chunking()
    test_statistics_dataclass()
    test_error_paths()
    test_reingest_idempotency()
    test_performance_10k()
    test_category_from_tags()

    print()
    print("=" * 60)
    print(f"PASS: {_PASS}")
    print(f"FAIL: {_FAIL}")
    print("=" * 60)
    if _FAIL:
        print("Failures:")
        for entry in _FAILURES:
            print(f"  FAIL  {entry}")
        return 1
    print("All Firestore uploader checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
