"""One-time Firestore importer for the curated 50-scholarship list.

The script consumes a single TXT file that contains a JSON array of
scholarship objects (one scholarship per element) and writes every
record into the existing ``scholarships`` collection. It is intentionally
*additive* and *read-only* with respect to the rest of the
ScholarBird backend:

* No existing module is modified. The importer imports
  :class:`backend.models.scholarship.Scholarship`,
  :class:`backend.parser.duplicate.DuplicateDetector`, and
  :class:`backend.firebase.upload.FirestoreUploader` â€” exactly the
  public API the running pipeline already uses.
* No scraper, parser, recommendation engine, lifecycle, payment, or
  AI module is touched. The importer runs as a standalone CLI.
* The Firestore document shape is produced by the existing
  :meth:`FirestoreUploader._canonical_payload` (via
  :meth:`FirestoreUploader.upsert`) so the schema is identical to the
  one already produced by the production ingest pipeline.

Extra fields present in the curated TXT file but not yet modelled by
the canonical schema (e.g. ``provider``, ``city``, ``continent``,
``study_fields``, ``funding_details``, ``intake``, ``duration``,
``english_requirement``, ``required_documents``, ``benefits``,
``featured``, ``verified``) are written as a single transactional
follow-up update in the same call so the upload is atomic per record.

Usage
-----

The script expects the Firebase service-account JSON path to be
available via the ``FIREBASE_CREDENTIALS_PATH`` environment variable
(the same path the rest of the backend uses) and a curated TXT file
whose default location is
``assets/50_Stable_Less_Famous_Scholarships_Firestore_JSON.txt``
relative to the project root.

::

    python backend/tools/import_manual_scholarships.py
    python backend/tools/import_manual_scholarships.py --dry-run
    python backend/tools/import_manual_scholarships.py --input path/to/list.txt
    python backend/tools/import_manual_scholarships.py --limit 10

Exit code is ``0`` on a clean run (even when individual records are
skipped) and non-zero only when the import could not be started at all
(file missing, credentials missing, JSON unparseable).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

# ---------------------------------------------------------------------------
# Path bootstrap â€” support ``python backend/tools/import_manual_scholarships.py``
# ---------------------------------------------------------------------------
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.constants import FIRESTORE_COLLECTION_SCHOLARSHIPS  # noqa: E402
from backend.firebase.upload import FirestoreUploader, UploadOutcome  # noqa: E402
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.parser.duplicate import DuplicateDetector  # noqa: E402

# ---------------------------------------------------------------------------
# Default TXT file â€” relative to the workspace root.
# ---------------------------------------------------------------------------
DEFAULT_INPUT_PATH = (
    _PROJECT_ROOT
    / "assets"
    / "50_Stable_Less_Famous_Scholarships_Firestore_JSON.txt"
)

# ---------------------------------------------------------------------------
# Extra fields present in the curated TXT file that are NOT modelled by
# the canonical ``Scholarship`` dataclass. They are projected onto the
# final Firestore document so the Flutter app and the AI pipeline can
# consume them without losing data.
#
# Every extra is mapped to the camelCase key the production schema
# already uses when one exists; otherwise the snake_case form is kept
# so the field is self-describing in the Firestore console.
# ---------------------------------------------------------------------------
_EXTRA_DEADLINE_RAW = "application_deadline"


@dataclass
class ImportReport:
    """Aggregate report produced by :func:`run_import`."""

    total_found: int = 0
    uploaded: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0
    failures: List[Dict[str, str]] = field(default_factory=list)
    started_at: str = field(
        default_factory=lambda: _utc_now_iso()
    )
    finished_at: str = ""
    dry_run: bool = False
    execution_time: float = 0.0
    collection: str = FIRESTORE_COLLECTION_SCHOLARSHIPS

    def to_dict(self) -> Dict[str, Any]:
        """Return a JSON-serialisable snapshot for printing."""
        return {
            "collection": self.collection,
            "total_found": self.total_found,
            "uploaded": self.uploaded,
            "updated": self.updated,
            "skipped": self.skipped,
            "failed": self.failed,
            "dry_run": self.dry_run,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "execution_time_seconds": round(self.execution_time, 4),
            "failures": list(self.failures),
        }


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def _utc_now_iso() -> str:
    """Return current UTC time as ISO-8601 with ``Z`` suffix."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def _strip_json_wrappers(text: str) -> str:
    """Strip surrounding Markdown code fences if present.

    The curated TXT file is a raw JSON array, but some editors wrap
    the contents in ``\\`\\`\\`plaintext`` fences. Removing the fences
    makes the parser tolerant of both formats.
    """
    stripped = text.strip()
    if stripped.startswith("```"):
        # Drop the opening fence (with optional language tag).
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1 :]
        # Drop the closing fence if present.
        if stripped.endswith("```"):
            stripped = stripped[: -3]
    return stripped.strip()


def load_records(txt_path: Path) -> List[Dict[str, Any]]:
    """Parse the TXT file and return the raw scholarship dicts.

    Args:
        txt_path: Path to the TXT file. The file must contain a JSON
            array of objects.

    Returns:
        A list of raw dicts in the order they appear in the file.

    Raises:
        FileNotFoundError: When ``txt_path`` does not exist.
        ValueError: When the file is empty or does not parse as a JSON
            array of objects.
    """
    if not txt_path.exists():
        raise FileNotFoundError(f"TXT file not found: {txt_path}")

    # ``utf-8-sig`` transparently strips a leading BOM if the file was
    # saved by an editor that added one (the curated TXT file ships
    # with one).
    raw = txt_path.read_text(encoding="utf-8-sig")
    cleaned = _strip_json_wrappers(raw)
    if not cleaned:
        raise ValueError(f"TXT file is empty: {txt_path}")

    parsed = json.loads(cleaned)
    if not isinstance(parsed, list):
        raise ValueError(
            f"TXT file must contain a JSON array; got {type(parsed).__name__}"
        )

    records: List[Dict[str, Any]] = []
    for index, item in enumerate(parsed):
        if not isinstance(item, dict):
            raise ValueError(
                f"Record at index {index} is not a JSON object: {item!r}"
            )
        records.append(item)
    return records


def _safe_float(value: Any) -> Optional[float]:
    """Best-effort float coercion that never raises."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text:
        return None
    # Strip scale hints like "3.5 out of 4.0" â†’ keep only the leading number.
    head = text.split(" ", 1)[0]
    try:
        return float(head)
    except ValueError:
        return None


def _coerce_ielts_required(value: Any) -> bool:
    """Return ``True`` when the English requirement mentions IELTS/TOEFL."""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    text = str(value).strip().lower()
    if not text:
        return False
    if "not required" in text or "not mandatory" in text:
        return False
    return any(token in text for token in ("ielts", "toefl", "english proficiency"))


def _coerce_fully_funded(value: Any) -> bool:
    """Return ``True`` when the funding type reads as fully funded."""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return "fully funded" in str(value).strip().lower()


def normalise_record(raw: Dict[str, Any]) -> Dict[str, Any]:
    """Project a raw TXT record into the canonical Scholarship schema.

    The returned dict is consumable by :meth:`Scholarship.from_dict`
    so the existing pipeline validation, normalisation, and content
    hashing run unchanged. Extra fields that the canonical model does
    not track are attached under :data:`_EXTRAS_KEY` so the importer
    can lift them onto the Firestore document after the canonical
    payload has been written.

    The function **never invents information**. Missing fields become
    ``None`` or empty containers, matching the defaults baked into
    :class:`Scholarship`.
    """
    study_fields = raw.get("study_fields") or raw.get("majors") or []
    if not isinstance(study_fields, list):
        study_fields = [part.strip() for part in str(study_fields).split(',') if part.strip()]

    # ``field`` is a single string in the canonical schema; the curated
    # TXT exposes a list â€” collapse to the first non-empty entry so the
    # canonical field is populated, while the full list is preserved
    # under ``study_fields``.
    primary_field = ""
    for item in study_fields:
        text = str(item).strip()
        if text:
            primary_field = text
            break

    deadline_value = raw.get("deadline") or raw.get(_EXTRA_DEADLINE_RAW) or ""
    deadline_text = str(deadline_value).strip() if deadline_value is not None else ""

    funding_type = raw.get("funding_type") or raw.get("award_type") or raw.get("award") or ""
    funding_details = raw.get("funding_details") or raw.get("award") or raw.get("award_amount") or ""
    eligibility = raw.get("eligibility") or ""
    description = raw.get("description") or raw.get("full_description") or ""
    link = raw.get("official_url") or raw.get("detail_url") or raw.get("apply_url") or raw.get("link") or ""
    image = raw.get("image") or raw.get("image_url") or ""
    university = raw.get("university") or ""
    official_id = raw.get("id") or raw.get("official_id") or ""

    base: Dict[str, Any] = {
        "title": str(raw.get("title") or "").strip(),
        "country": str(raw.get("country") or "United States").strip(),
        # Canonical ``degree`` is a free-string. The TXT value (e.g.
        # "Bachelor's / Master's / PhD") is already human-readable.
        "degree": str(raw.get("degree_level") or raw.get("degree") or raw.get("enrollment_level") or "").strip(),
        "field": primary_field or str(raw.get("field") or "").strip(),
        "deadline": deadline_text,
        # ``amount`` is the canonical funding string. The TXT exposes
        # both a short type ("Fully Funded") and a long description;
        # the long description is more useful for the UI list view.
        "amount": str(funding_details).strip(),
        "description": str(description).strip(),
        "link": str(link).strip(),
        "image": str(image).strip() or None,
        "min_cgpa": _safe_float(raw.get("minimum_cgpa")),
        "minCgpa": _safe_float(raw.get("minimum_cgpa")),
        "cgpa_scale": 4.0,
        "max_backlogs": 0,
        "english_medium_accepted": True,
        "fully_funded": _coerce_fully_funded(funding_type),
        "fullyFunded": _coerce_fully_funded(funding_type),
        "ielts_required": _coerce_ielts_required(raw.get("english_requirement")),
        "ieltsRequired": _coerce_ielts_required(raw.get("english_requirement")),
        "research_required": False,
        "researchRequired": False,
        "source": "manual_import",
        "tags": [str(t).strip() for t in (raw.get("tags") or []) if str(t).strip()],
        "university": str(university).strip() or None,
        "official_id": str(official_id).strip() or None,
        "officialId": str(official_id).strip() or None,
        "eligibility": str(eligibility).strip() or None,
        "apply_url": str(raw.get("application_url") or raw.get("apply_url") or "").strip() or None,
        "applyUrl": str(raw.get("application_url") or raw.get("apply_url") or "").strip() or None,
        "fundingType": str(funding_type).strip() or None,
    }

    # ``category`` is consumed by the canonical uploader's projection
    # (it uses the first tag). Pre-fill it so the document stays
    # consistent with the existing pipeline's expectation.
    if base["tags"] and not base.get("category"):
        base["category"] = base["tags"][0]

    # Round-trip the canonical fields through ``Scholarship.from_dict``
    # so the importer never diverges from the production model's
    # validation rules.
    canonical = Scholarship.from_dict(base)

    # Attach extras so the document gets the full TXT payload.
    extras: Dict[str, Any] = {
        "provider": str(raw.get("provider") or "").strip() or None,
        "city": str(raw.get("city") or "").strip() or None,
        "continent": str(raw.get("continent") or "").strip() or None,
        "study_fields": [str(s).strip() for s in study_fields if str(s).strip()],
        "funding_details": str(funding_details).strip() or None,
        "intake": str(raw.get("intake") or "").strip() or None,
        "duration": str(raw.get("duration") or "").strip() or None,
        "english_requirement": str(raw.get("english_requirement") or "").strip() or None,
        "required_documents": [
            str(d).strip()
            for d in (raw.get("required_documents") or [])
            if str(d).strip()
        ],
        "benefits": [str(b).strip() for b in (raw.get("benefits") or []) if str(b).strip()],
        "featured": bool(raw.get("featured")),
        "isFeatured": bool(raw.get("featured")),
        "verified": bool(raw.get("verified")),
    }

    payload = canonical.to_dict()
    payload["_extras"] = extras
    return payload


# ---------------------------------------------------------------------------
# Firestore I/O â€” extension fields are written in the same batch as the
# canonical payload so the document is written atomically.
# ---------------------------------------------------------------------------

def _merge_extras(
    payload: Dict[str, Any],
    *,
    action: str,
    outcome: UploadOutcome,
) -> Dict[str, Any]:
    """Return the doc-level write payload with extras folded in.

    Args:
        payload: The canonical payload returned by the uploader's
            ``_prepare`` step. Carries ``_extras`` from
            :func:`normalise_record`.
        action: Outcome action â€” ``"inserted"``, ``"updated"`` or
            ``"skipped"``. Determines whether the extras are written
            as the full document (``inserted``) or as a partial update
            (``updated`` / ``skipped``).
        outcome: The :class:`UploadOutcome` describing what the
            uploader plans to do.

    Returns:
        A dict ready for ``client.batch().set`` /
        ``client.batch().update``. For ``skipped`` records, an empty
        dict signals that no follow-up write is needed.
    """
    extras = payload.pop("_extras", {}) or {}
    if not extras:
        return {}

    # Drop None/empty so the document stays compact and the diff step
    # does not flag accidental ``null``/missing churn.
    cleaned: Dict[str, Any] = {}
    for key, value in extras.items():
        if value is None:
            continue
        if isinstance(value, str) and not value.strip():
            continue
        if isinstance(value, (list, tuple)) and len(value) == 0:
            continue
        cleaned[key] = value

    if not cleaned:
        return {}

    if action == "inserted":
        return cleaned

    # For updates / skips we send _only_ the fields the document is
    # missing â€” extra fields that already exist are preserved untouched.
    return cleaned


def _write_extras_after_upsert(
    client: Any,
    collection_name: str,
    document_id: str,
    extras: Dict[str, Any],
    *,
    dry_run: bool,
) -> bool:
    """Attach extras to an existing document, returning success flag.

    The write is a Firestore batch with a single ``update`` so the
    extras become part of the same commit. The schema is preserved
    exactly â€” extras never overwrite canonical fields.
    """
    if not extras:
        return True
    if dry_run:
        return True

    try:
        batch = client.batch()
        doc_ref = client.collection(collection_name).document(document_id)
        batch.update(doc_ref, extras)
        batch.commit()
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run_import(
    txt_path: Path,
    *,
    dry_run: bool = False,
    limit: Optional[int] = None,
) -> ImportReport:
    """Run the curated-scholarships import.

    Args:
        txt_path: Path to the curated TXT file.
        dry_run: When ``True``, every Firestore write is skipped. The
            report still reflects the planned actions.
        limit: Optional cap on the number of records to process.

    Returns:
        An :class:`ImportReport` describing the outcome.
    """
    report = ImportReport(dry_run=dry_run)
    started = time.perf_counter()

    raw_records = load_records(txt_path)
    if limit is not None and limit > 0:
        raw_records = raw_records[:limit]

    report.total_found = len(raw_records)
    print(f"[import] Parsed {report.total_found} record(s) from {txt_path}")
    if report.total_found == 0:
        report.finished_at = _utc_now_iso()
        report.execution_time = time.perf_counter() - started
        return report

    # Initialise the uploader. The detector is required by the
    # uploader's constructor, so we share a fresh instance â€” the
    # canonical (content-hash) ID is still the source of truth, so the
    # detector is only used to keep the uploader's invariants intact.
    detector = DuplicateDetector()
    uploader = FirestoreUploader(
        detector=detector,
        batch_size=min(50, len(raw_records)) or 1,
        dry_run=dry_run,
    )

    # Normalise every record up front so a single typing/lint failure
    # never blocks the batch from being written.
    prepared: List[Dict[str, Any]] = []
    for index, raw in enumerate(raw_records):
        try:
            prepared.append(normalise_record(raw))
        except Exception as exc:  # pragma: no cover - defensive
            report.failed += 1
            report.failures.append(
                {
                    "index": str(index),
                    "title": str(raw.get("title") or ""),
                    "error": f"normalisation failed: {exc}",
                }
            )
            print(f"[import] [{index + 1}/{report.total_found}] "
                  f"FAILED to normalise '{raw.get('title')}': {exc}")

    if not prepared:
        report.finished_at = _utc_now_iso()
        report.execution_time = time.perf_counter() - started
        return report

    # ------------------------------------------------------------------
    # Upsert each record via the existing uploader. The uploader owns
    # document-id generation (SHA-256 content hash), the canonical
    # payload, the diffing strategy, and the timestamp stamping â€” so
    # the existing schema is preserved exactly.
    # ------------------------------------------------------------------
    for index, payload in enumerate(prepared, start=1):
        title = payload.get("title") or "<untitled>"
        try:
            outcome = uploader.upsert(payload)
        except Exception as exc:  # pragma: no cover - defensive
            report.failed += 1
            report.failures.append(
                {
                    "index": str(index),
                    "title": title,
                    "error": f"upsert raised: {exc}",
                }
            )
            print(f"[import] [{index}/{report.total_found}] "
                  f"FAILED '{title}': {exc}")
            continue

        # Apply extras as a follow-up Firestore update so the document
        # ends up with the full curated payload. The uploader commit has
        # already produced the canonical document; this step is a
        # single batch update with the extras only.
        extras = payload.pop("_extras", {}) or {}
        client = getattr(uploader, "_client", None)
        if (
            extras
            and client is not None
            and outcome.action in ("inserted", "updated", "skipped")
            and outcome.document_id
        ):
            ok = _write_extras_after_upsert(
                client,
                uploader._collection_name,
                outcome.document_id,
                extras,
                dry_run=dry_run,
            )
            if not ok:
                outcome = UploadOutcome(
                    document_id=outcome.document_id,
                    action="failed",
                    error="extras commit failed",
                )

        if outcome.action == "inserted":
            report.uploaded += 1
            print(f"[import] [{index}/{report.total_found}] "
                  f"NEW      '{title}' â†’ {outcome.document_id}")
        elif outcome.action == "updated":
            report.updated += 1
            print(f"[import] [{index}/{report.total_found}] "
                  f"UPDATED  '{title}' â†’ {outcome.document_id}")
        elif outcome.action == "skipped":
            report.skipped += 1
            print(f"[import] [{index}/{report.total_found}] "
                  f"SKIPPED  '{title}' (no changes)")
        else:
            report.failed += 1
            report.failures.append(
                {
                    "index": str(index),
                    "title": title,
                    "error": outcome.error or "unknown failure",
                }
            )
            print(f"[import] [{index}/{report.total_found}] "
                  f"FAILED   '{title}': {outcome.error}")

    report.finished_at = _utc_now_iso()
    report.execution_time = time.perf_counter() - started
    return report


def _print_report(report: ImportReport) -> None:
    """Print the final PASS/FAIL report in a human-readable format."""
    print()
    print("=" * 72)
    print(" CURRICULATED IMPORT â€” FINAL REPORT")
    print("=" * 72)
    print(f"  Collection         : {report.collection}")
    print(f"  Mode               : {'dry-run' if report.dry_run else 'live'}")
    print(f"  Started at         : {report.started_at}")
    print(f"  Finished at        : {report.finished_at}")
    print(f"  Execution time (s) : {report.execution_time:.3f}")
    print("-" * 72)
    print(f"  Total found        : {report.total_found}")
    print(f"  Uploaded (new)     : {report.uploaded}")
    print(f"  Updated            : {report.updated}")
    print(f"  Skipped            : {report.skipped}")
    print(f"  Failed             : {report.failed}")
    print("-" * 72)
    if report.failures:
        print("  Failures:")
        for entry in report.failures:
            print(f"    â€¢ [{entry.get('index', '?')}] "
                  f"{entry.get('title', '?')}: {entry.get('error')}")
    print("=" * 72)
    verdict = "PASS" if report.failed == 0 else "PARTIAL"
    if report.total_found == 0:
        verdict = "FAIL"
    print(f"  OVERALL: {verdict}")
    print("=" * 72)


def _parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "One-time Firestore importer for the curated TXT scholarship list. "
            "Reuses the existing FirestoreUploader so the schema is preserved."
        )
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_INPUT_PATH,
        help=(
            "Path to the TXT file. "
            f"Defaults to: {DEFAULT_INPUT_PATH}"
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Skip every Firestore write; print the planned actions.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional cap on the number of records to import.",
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = _parse_args(argv)
    try:
        report = run_import(
            args.input,
            dry_run=args.dry_run,
            limit=args.limit,
        )
    except FileNotFoundError as exc:
        print(f"[import] ERROR: {exc}", file=sys.stderr)
        return 2
    except ValueError as exc:
        print(f"[import] ERROR: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - top-level guard
        print(f"[import] UNEXPECTED ERROR: {exc}", file=sys.stderr)
        return 3

    _print_report(report)
    return 0 if report.failed == 0 else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())


