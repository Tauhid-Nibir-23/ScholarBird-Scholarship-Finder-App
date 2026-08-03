"""Entry point for the ScholarBird backend.

This module now runs the full ingestion pipeline::

    scraper (DAAD)
      -> normalize each record
      -> validate each record
      -> deduplicate via DuplicateDetector
      -> upload to Firestore via FirestoreUploader

Behaviour is intentionally idempotent and re-runnable:

* Document IDs are SHA-256 content hashes, so re-ingesting the same
  scholarship always lands on the same document.
* The uploader preserves ``created_at`` and refreshes ``updated_at``
  on updates, so a second run produces a no-op for unchanged records
  and an ``updated`` outcome for changed records.

The pipeline is gated by the ``DRY_RUN`` environment variable
(``"1"`` / ``"true"`` case-insensitive) — when set, the script
performs every read and decision but never writes to Firestore. This
is the recommended way to smoke-test the integration in CI.

Exit codes
----------
* ``0`` — pipeline ran without an unrecoverable error.
* ``1`` — Firebase configuration is missing (e.g. no credentials
  path) or the pipeline raised an unexpected exception.
* ``2`` — the pipeline ran but every record failed validation /
  dedupe; treated as a hard failure so broken scrapers are noticed.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Ensure the project root (which contains the ``backend`` package) is on
# ``sys.path`` regardless of how this file is invoked:
#   * ``python backend/main.py``  -> CWD is the project root.
#   * ``cd backend && python main.py`` -> CWD is ``backend/``.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.constants import APP_NAME, APP_VERSION  # noqa: E402
from backend.config.settings import get_settings  # noqa: E402
from backend.core.exceptions import FirebaseError, ValidationError  # noqa: E402
from backend.core.logger import configure_logging, get_logger  # noqa: E402
from backend.firebase import FirestoreUploader  # noqa: E402
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.parser.duplicate import DuplicateDetector  # noqa: E402
from backend.parser.normalize import normalize_scholarship  # noqa: E402
from backend.parser.quality import assess_scholarship_quality  # noqa: E402
from backend.parser.enrich import ScholarshipEnricher  # noqa: E402
from backend.parser.validator import validate_scholarship  # noqa: E402
from backend.scrapers.daad import DaadScraper  # noqa: E402

BANNER_WIDTH: int = 40
PIPELINE_NAME: str = "DAAD -> Normalize -> Validate -> Dedupe -> Firestore"


def _truthy(value: str | None) -> bool:
    """Return ``True`` when ``value`` is a non-empty truthy string."""
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _print_banner(dry_run: bool) -> None:
    """Print the foundation banner to stdout."""
    bar = "-" * BANNER_WIDTH
    print(bar)
    print(f"{APP_NAME} Initialized")
    print("Foundation Loaded Successfully")
    print(f"Version {APP_VERSION}")
    print(f"Pipeline: {PIPELINE_NAME}")
    print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
    print(bar)


def _collect_records(scraper: DaadScraper) -> list[Scholarship]:
    """Run the scraper and return the parsed :class:`Scholarship` list."""
    logger = get_logger(__name__)
    logger.info("Stage 1/5: scraping with %s", scraper.name)
    raw_content = scraper.fetch()
    records = scraper.parse(raw_content)
    logger.info("Scraper returned %d raw records", len(records))
    return records


def _normalize_and_validate(
    records: list[Scholarship],
) -> tuple[list[Scholarship], int]:
    """Normalise and validate every record; drop the invalid ones.

    Returns:
        A ``(kept_records, dropped_count)`` tuple. ``dropped`` is
        incremented for both normalisation failures and validation
        failures; the dropped record is logged for the operator.
    """
    logger = get_logger(__name__)
    logger.info("Stage 2/5: normalising records")
    normalised: list[Scholarship] = []
    enricher = ScholarshipEnricher()
    for record in records:
        quality = assess_scholarship_quality(record.to_dict())
        if not quality.accepted:
            logger.debug("Quality filter rejected %r: %s", record.title, quality.reason)
            continue
        try:
            normalised_scholarship = enricher.enrich(record).normalize()
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Normalisation failed for %r: %s",
                           record.title, exc)
            continue
        normalised.append(normalised_scholarship)

    logger.info("Stage 3/5: validating %d records", len(normalised))
    kept: list[Scholarship] = []
    dropped = 0
    for record in normalised:
        try:
            is_valid = record.validate(raise_on_error=False)
        except ValidationError as exc:
            logger.warning("Validation raised for %r: %s", record.title, exc)
            dropped += 1
            continue
        if not is_valid:
            logger.debug("Validation rejected %r", record.title)
            dropped += 1
            continue
        # Re-run the parser-level validator so the model round-trip
        # (normalize -> validate) is exercised in addition to the
        # model-internal path. Belt and braces.
        result = validate_scholarship(record.to_dict())
        if not result.is_valid:
            logger.debug("Parser rejected %r: %s", record.title, result.reason)
            dropped += 1
            continue
        kept.append(record)
    logger.info("Validation kept %d records, dropped %d", len(kept), dropped)
    return kept, dropped


def _dedupe(
    records: list[Scholarship],
    detector: DuplicateDetector,
) -> tuple[list[Scholarship], int]:
    """Deduplicate against the detector.

    Returns:
        ``(kept_records, dropped_count)``. ``dropped`` counts every
        record the detector flagged as a duplicate of something
        already in this run.
    """
    logger = get_logger(__name__)
    logger.info("Stage 4/5: deduplicating %d records", len(records))
    kept: list[Scholarship] = []
    dropped = 0
    for record in records:
        result = detector.ingest(record.to_dict())
        if result.is_duplicate:
            logger.debug("Duplicate dropped: %r (matched_by=%s)",
                         record.title, result.matched_by)
            dropped += 1
            continue
        kept.append(record)
    logger.info("Dedup kept %d records, dropped %d", len(kept), dropped)
    return kept, dropped


def _upload(
    records: list[Scholarship],
    detector: DuplicateDetector,
    dry_run: bool,
) -> object:
    """Persist the surviving records to Firestore."""
    logger = get_logger(__name__)
    logger.info("Stage 5/5: uploading %d records (dry_run=%s)",
                len(records), dry_run)
    uploader = FirestoreUploader(detector=detector, dry_run=dry_run)
    summary = uploader.upsert_many(records)
    logger.info(
        "Upload summary: new=%d updated=%d skipped=%d failed=%d "
        "batches=%d time=%.3fs",
        summary.new,
        summary.updated,
        summary.skipped,
        summary.failed,
        summary.batch_count,
        summary.execution_time,
    )
    return summary


def _resolve_dry_run() -> bool:
    """Return the effective dry-run flag.

    Priority: ``DRY_RUN`` env var > ``FIRESTORE_DRY_RUN`` env var >
    ``False``. The first two are accepted so an operator can toggle
    the behaviour without editing the script.
    """
    return _truthy(os.getenv("DRY_RUN")) or _truthy(
        os.getenv("FIRESTORE_DRY_RUN")
    )


def main() -> int:
    """Run the ingestion pipeline. See module docstring for details."""
    settings = get_settings()
    configure_logging(level=settings.log_level)
    logger = get_logger(__name__)

    dry_run = _resolve_dry_run()
    logger.info("Bootstrapping %s v%s (env=%s, dry_run=%s)",
                APP_NAME, APP_VERSION, settings.env, dry_run)
    _print_banner(dry_run)

    # ------------------------------------------------------------------
    # Pipeline
    # ------------------------------------------------------------------
    try:
        scraper = DaadScraper()
        raw_records = _collect_records(scraper)
    except Exception as exc:
        logger.exception("Scraper stage failed")
        print(f"Scraper stage failed: {exc}", file=sys.stderr)
        return 1

    normalised_records, _normalisation_dropped = _normalize_and_validate(
        raw_records
    )

    detector = DuplicateDetector()
    deduped_records, _duplicates_dropped = _dedupe(normalised_records, detector)

    try:
        summary = _upload(deduped_records, detector, dry_run)
    except FirebaseError as exc:
        logger.exception("Firestore upload failed")
        print(f"Firestore upload failed: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # pragma: no cover - defensive
        logger.exception("Unexpected upload failure")
        print(f"Unexpected upload failure: {exc}", file=sys.stderr)
        return 1

    # ------------------------------------------------------------------
    # Reporting
    # ------------------------------------------------------------------
    summary_dict = summary.to_dict()
    print("Pipeline summary:")
    for key, value in summary_dict.items():
        print(f"  {key}: {value}")

    if raw_records and summary.failed == len(raw_records):
        logger.error("Every record failed; aborting with exit code 2")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
