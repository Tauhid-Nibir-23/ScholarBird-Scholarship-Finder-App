"""Plugin-based scraper orchestration for the ScholarBird backend.

The :class:`ScraperOrchestrator` is the single entry point that owns
the full ingestion pipeline:

::

    registry.discover()
        -> for each scraper:
              scrape -> normalize -> validate -> dedupe -> Firestore

Responsibilities
----------------

* resolve which scrapers to run (registry + ``Settings.enabled_scrapers``)
* run them in parallel or sequentially based on configuration
* isolate failures — one scraper crash never aborts the whole run
* aggregate per-scraper statistics into a single
  :class:`OrchestratorSummary`
* print a human-readable console report when the run finishes

Design goals
------------

* **Zero coupling to a particular scraper.** The orchestrator only
  depends on :class:`BaseScraper`; new scrapers are picked up by the
  registry without any code changes here.
* **Reuse existing modules.** Normalization, validation, deduplication,
  and Firestore upload are delegated to the engines the project
  already ships in :mod:`backend.parser` and :mod:`backend.firebase`.
* **Resource sharing.** A single :class:`DuplicateDetector` and
  :class:`FirestoreUploader` are created per worker (sequential mode
  reuses them across all scrapers; parallel mode builds one of each
  per worker so concurrent scrapers do not share mutable state).
* **Testability.** The orchestrator accepts custom registries,
  settings, and uploader factories, which keeps the test-suite
  offline.
"""

from __future__ import annotations

import inspect
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

# Ensure the project root is importable when this module is run as
# ``python backend/orchestrator.py``.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.settings import Settings, get_settings
from backend.core.exceptions import FirebaseError, ScraperException
from backend.core.logger import configure_logging, get_logger
from backend.firebase import FirestoreUploader, UploadSummary
from backend.models.scholarship import Scholarship
from backend.parser.duplicate import DuplicateDetector, DuplicateResult
from backend.parser.quality import assess_scholarship_quality
from backend.parser.enrich import ScholarshipEnricher
from backend.parser.validator import validate_scholarship
from backend.scrapers.base_scraper import BaseScraper
from backend.scrapers.registry import ScraperEntry, ScraperRegistry

_logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------


@dataclass
class ScraperStats:
    """Per-scraper statistics collected during a single run.

    Each counter is incremented by the orchestrator's pipeline driver
    so the public surface can aggregate them safely even when running
    in parallel.
    """

    name: str
    elapsed_seconds: float = 0.0
    records_found: int = 0
    valid: int = 0
    invalid: int = 0
    inserted: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0
    error: Optional[str] = None

    @property
    def ok(self) -> bool:
        """``True`` when the scraper completed without raising."""
        return self.error is None

    def as_dict(self) -> Dict[str, Any]:
        """Return a JSON-serialisable snapshot of the counters."""
        return {
            "name": self.name,
            "elapsed_seconds": round(self.elapsed_seconds, 4),
            "records_found": self.records_found,
            "valid": self.valid,
            "invalid": self.invalid,
            "inserted": self.inserted,
            "updated": self.updated,
            "skipped": self.skipped,
            "failed": self.failed,
            "error": self.error,
        }


@dataclass
class OrchestratorSummary:
    """Aggregate statistics for one ``ScraperOrchestrator.run`` call."""

    scrapers: List[ScraperStats] = field(default_factory=list)
    total_new: int = 0
    total_updated: int = 0
    total_skipped: int = 0
    total_failed: int = 0
    total_records_found: int = 0
    total_valid: int = 0
    total_invalid: int = 0
    elapsed_seconds: float = 0.0
    parallel: bool = False
    max_workers: int = 1

    def as_dict(self) -> Dict[str, Any]:
        """Return a JSON-serialisable snapshot for logging."""
        return {
            "total_scrapers": len(self.scrapers),
            "total_new": self.total_new,
            "total_updated": self.total_updated,
            "total_skipped": self.total_skipped,
            "total_failed": self.total_failed,
            "total_records_found": self.total_records_found,
            "total_valid": self.total_valid,
            "total_invalid": self.total_invalid,
            "elapsed_seconds": round(self.elapsed_seconds, 4),
            "parallel": self.parallel,
            "max_workers": self.max_workers,
            "scrapers": [stats.as_dict() for stats in self.scrapers],
        }


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------


#: Type alias for a callable that builds a fresh :class:`FirestoreUploader`.
UploaderFactory = Callable[[DuplicateDetector], FirestoreUploader]


def _default_uploader_factory(
    detector: DuplicateDetector,
    *,
    dry_run: bool,
) -> FirestoreUploader:
    """Default factory that constructs a real :class:`FirestoreUploader`."""
    return FirestoreUploader(detector=detector, dry_run=dry_run)


class ScraperOrchestrator:
    """Coordinate the registry, the pipeline, and Firestore uploads.

    Args:
        registry: Optional pre-built :class:`ScraperRegistry`. When
            ``None``, :meth:`ScraperRegistry.discover` is used.
        settings: Optional :class:`Settings`. Defaults to
            :func:`get_settings` so the orchestrator respects
            ``ENABLE_PARALLEL`` / ``MAX_WORKERS`` / ``ENABLED_SCRAPERS``
            without code changes.
        dry_run: When ``True``, every record is deduped but the
            Firestore uploader is constructed in dry-run mode. The
            default honours ``DRY_RUN`` / ``FIRESTORE_DRY_RUN``.
        uploader_factory: Optional factory used to build the
            :class:`FirestoreUploader`. Tests inject a fake; production
            callers leave it at ``None``.
        log_level: Optional log level forwarded to
            :func:`configure_logging`. ``None`` keeps the existing
            configuration untouched.
    """

    def __init__(
        self,
        registry: Optional[ScraperRegistry] = None,
        settings: Optional[Settings] = None,
        *,
        dry_run: Optional[bool] = None,
        uploader_factory: Optional[UploaderFactory] = None,
        log_level: Optional[str] = None,
    ) -> None:
        # ``registry or ScraperRegistry.discover()`` would fall through
        # to ``discover()`` for an empty-but-truthy registry because
        # :class:`ScraperRegistry` defines ``__len__``; check ``None``
        # explicitly so callers can pass an empty registry without
        # triggering network discovery.
        self._registry: ScraperRegistry = (
            registry if registry is not None else ScraperRegistry.discover()
        )
        self._settings: Settings = settings or get_settings()
        self._dry_run: bool = (
            dry_run
            if dry_run is not None
            else self._resolve_dry_run()
        )
        self._uploader_factory: UploaderFactory = (
            uploader_factory
            if uploader_factory is not None
            else lambda detector: _default_uploader_factory(
                detector, dry_run=self._dry_run
            )
        )
        if log_level is not None:
            configure_logging(level=log_level)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def registry(self) -> ScraperRegistry:
        """Return the active registry (read-only)."""
        return self._registry

    @property
    def settings(self) -> Settings:
        return self._settings

    @property
    def dry_run(self) -> bool:
        return self._dry_run

    def run(self) -> OrchestratorSummary:
        """Execute every requested scraper and return the summary.

        The flow:

        1. Resolve the list of scrapers from the registry and
           ``Settings.enabled_scrapers``.
        2. Build a single :class:`DuplicateDetector` and a single
           :class:`FirestoreUploader` shared across scrapers (or one
           per worker when running in parallel).
        3. Dispatch scrapers either sequentially or via
           :class:`ThreadPoolExecutor` — controlled by
           ``Settings.enable_parallel`` and ``Settings.max_workers``.
        4. Per-scraper: scrape → normalize → validate → dedupe →
           upload. Failures are isolated; the remaining scrapers
           continue.
        5. Return an :class:`OrchestratorSummary` and print a
           human-friendly report to stdout.

        Returns:
            The aggregated :class:`OrchestratorSummary`.
        """
        entries = self._select_entries()
        summary = OrchestratorSummary(
            parallel=self._settings.enable_parallel,
            max_workers=max(1, self._settings.max_workers),
        )

        if not entries:
            _logger.warning("Orchestrator: no scrapers to run.")
            self._print_summary(summary)
            return summary

        self._print_loading(entries)

        started = time.perf_counter()
        try:
            if self._settings.enable_parallel and self._settings.max_workers > 1:
                self._run_parallel(entries, summary)
            else:
                self._run_sequential(entries, summary)
        finally:
            summary.elapsed_seconds = time.perf_counter() - started

        self._print_summary(summary)
        return summary

    # ------------------------------------------------------------------
    # Dispatchers
    # ------------------------------------------------------------------

    def _run_sequential(
        self,
        entries: List[ScraperEntry],
        summary: OrchestratorSummary,
    ) -> None:
        """Run every scraper one after another (default fallback)."""
        detector = DuplicateDetector()
        uploader = self._uploader_factory(detector)
        for entry in entries:
            self._print_running(entry)
            stats = self._run_one(entry, detector, uploader)
            summary.scrapers.append(stats)
            self._fold(summary, stats)
            self._print_scraper_done(stats)

    def _run_parallel(
        self,
        entries: List[ScraperEntry],
        summary: OrchestratorSummary,
    ) -> None:
        """Run every scraper via a :class:`ThreadPoolExecutor`.

        Each worker builds a fresh :class:`DuplicateDetector` and
        :class:`FirestoreUploader` so concurrent scrapers do not share
        mutable state. The aggregate counters from each run are
        folded into the shared summary at the end.
        """
        max_workers = max(1, min(self._settings.max_workers, len(entries)))
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            future_to_entry = {
                pool.submit(self._run_one_isolated, entry): entry
                for entry in entries
            }
            for future in as_completed(future_to_entry):
                entry = future_to_entry[future]
                try:
                    stats = future.result()
                except Exception as exc:  # noqa: BLE001 - isolation
                    _logger.exception(
                        "Worker for scraper %s raised unexpectedly",
                        entry.name,
                    )
                    stats = ScraperStats(
                        name=entry.name,
                        error=f"{type(exc).__name__}: {exc}",
                    )
                summary.scrapers.append(stats)
                self._fold(summary, stats)

        # Preserve a deterministic order in the output.
        summary.scrapers.sort(key=lambda s: s.name)

    # ------------------------------------------------------------------
    # Single-scraper pipeline
    # ------------------------------------------------------------------

    def _run_one(
        self,
        entry: ScraperEntry,
        detector: DuplicateDetector,
        uploader: FirestoreUploader,
    ) -> ScraperStats:
        """Run the full pipeline for a single scraper using shared state.

        Args:
            entry: Scraper description from the registry.
            detector: Project-wide :class:`DuplicateDetector`.
            uploader: Project-wide :class:`FirestoreUploader`.

        Returns:
            A populated :class:`ScraperStats`.
        """
        stats = ScraperStats(name=entry.name)
        started = time.perf_counter()
        try:
            with self._instantiate(entry) as scraper:
                records = self._safe_run(scraper, stats)
            self._validate_dedupe_upload(records, detector, uploader, stats)
        except ScraperException as exc:
            stats.error = f"{type(exc).__name__}: {exc}"
            _logger.error(
                "Scraper %s failed: %s", entry.name, stats.error, exc_info=exc,
            )
        except Exception as exc:  # noqa: BLE001 - isolation boundary
            stats.error = f"{type(exc).__name__}: {exc}"
            _logger.exception("Scraper %s crashed", entry.name)
        finally:
            stats.elapsed_seconds = time.perf_counter() - started
        return stats

    def _run_one_isolated(self, entry: ScraperEntry) -> ScraperStats:
        """Run a single scraper with its own detector and uploader.

        Used by the parallel dispatcher so concurrent scrapers do not
        share mutable state. Each worker builds a fresh
        :class:`DuplicateDetector` and calls the uploader factory to
        obtain a per-worker :class:`FirestoreUploader`.

        Args:
            entry: Scraper description from the registry.

        Returns:
            A populated :class:`ScraperStats`.
        """
        detector = DuplicateDetector()
        uploader = self._uploader_factory(detector)
        return self._run_one(entry, detector, uploader)

    def _safe_run(
        self,
        scraper: BaseScraper,
        stats: ScraperStats,
    ) -> List[Scholarship]:
        """Execute ``scraper.run()`` and record the raw record count.

        Args:
            scraper: Instantiated scraper.
            stats: Stats object mutated in place.

        Returns:
            The list of :class:`Scholarship` records from the scraper.
        """
        records = scraper.run()
        stats.records_found = len(records)
        _logger.info(
            "Scraper %s produced %d raw record(s)",
            scraper.name,
            len(records),
        )
        return records

    def _validate_dedupe_upload(
        self,
        records: Iterable[Scholarship],
        detector: DuplicateDetector,
        uploader: FirestoreUploader,
        stats: ScraperStats,
    ) -> None:
        """Normalize, validate, dedupe, and upload ``records``.

        The method mirrors the public helpers used by ``main.py``:

        * :meth:`Scholarship.normalize` returns a new
          :class:`Scholarship` with normalised fields.
        * :meth:`Scholarship.validate` short-circuits on
          :class:`ValidationError`.
        * :func:`validate_scholarship` re-runs the parser-level
          rules on the normalised dict.
        * :meth:`DuplicateDetector.ingest` records the dedupe
          decision.
        * :meth:`FirestoreUploader.upsert_many` performs the
          Firestore batch upsert.

        Args:
            records: Iterable of :class:`Scholarship` instances.
            detector: Shared :class:`DuplicateDetector`.
            uploader: Shared :class:`FirestoreUploader`.
            stats: Stats object mutated in place.
        """
        # Stage 1: normalise. ``Scholarship.normalize`` returns a new
        # Scholarship with the transformed fields because the dataclass
        # is frozen.
        normalised: List[Scholarship] = []
        enricher = ScholarshipEnricher()
        for record in records:
            quality = assess_scholarship_quality(record.to_dict())
            if not quality.accepted:
                stats.invalid += 1
                _logger.debug("Quality filter rejected %r: %s", record.title, quality.reason)
                continue
            try:
                normalised_scholarship = enricher.enrich(record).normalize()
            except Exception as exc:  # noqa: BLE001 - defensive
                _logger.warning(
                    "Normalisation failed for %r: %s",
                    getattr(record, "title", "?"),
                    exc,
                )
                stats.invalid += 1
                continue
            normalised.append(normalised_scholarship)

        # Stage 2: validate. Run both ``Scholarship.validate`` (model
        # round-trip) and ``validate_scholarship`` (parser) so each
        # record is double-checked.
        kept: List[Scholarship] = []
        for record in normalised:
            try:
                model_ok = record.validate(raise_on_error=False)
            except Exception as exc:  # noqa: BLE001 - defensive
                _logger.debug(
                    "Validation raised for %r: %s",
                    getattr(record, "title", "?"),
                    exc,
                )
                stats.invalid += 1
                continue
            result = validate_scholarship(record.to_dict())
            if not model_ok or not result.is_valid:
                _logger.debug(
                    "Validation rejected %r: %s",
                    getattr(record, "title", "?"),
                    result.reason,
                )
                stats.invalid += 1
                continue
            kept.append(record)
            stats.valid += 1

        # Stage 3: dedupe. The detector indexes remembered records so a
        # subsequent ``FirestoreUploader.upsert_many`` call will skip
        # already-seen hashes.
        upload_records: List[Scholarship] = []
        for record in kept:
            snapshot = record.to_dict()
            outcome: DuplicateResult = detector.ingest(snapshot)
            if outcome.is_duplicate:
                stats.skipped += 1
                continue
            upload_records.append(record)

        if not upload_records:
            return

        # Stage 4: upload. The uploader itself reports the per-record
        # action; we only need to fold the totals into our stats.
        try:
            upload_summary: UploadSummary = uploader.upsert_many(
                upload_records
            )
        except FirebaseError as exc:
            _logger.error(
                "Firestore upload failed for scraper %s: %s",
                stats.name,
                exc,
            )
            stats.failed += len(upload_records)
            stats.error = stats.error or f"FirebaseError: {exc}"
            return

        stats.inserted += upload_summary.new
        stats.updated += upload_summary.updated
        stats.skipped += upload_summary.skipped
        stats.failed += upload_summary.failed

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _select_entries(self) -> List[ScraperEntry]:
        """Return the registry entries filtered by ``ENABLED_SCRAPERS``."""
        allowed = self._settings.enabled_scrapers
        entries = self._registry.list()
        if not allowed:
            return entries
        allowed_set = set(allowed)
        selected = [entry for entry in entries if entry.name in allowed_set]
        missing = allowed_set - {entry.name for entry in selected}
        for name in sorted(missing):
            _logger.warning(
                "Orchestrator: enabled scraper %r not found in registry",
                name,
            )
        return selected

    def _instantiate(self, entry: ScraperEntry) -> BaseScraper:
        """Build a fresh scraper instance for ``entry``.

        The constructor is invoked with no arguments when the
        classifier takes none (e.g. :class:`DaadScraper`). When the
        constructor requires a ``source_url`` (the
        :class:`BaseScraper` contract), the orchestrator passes the
        ``source_url`` declared on the class (``source_url`` attribute
        or defaulting to ``"about:blank"``).
        """
        cls = entry.cls
        try:
            return cls()  # type: ignore[call-arg]
        except TypeError:
            # The signature requires arguments. Use inspect to figure
            # out whether ``source_url`` is expected.
            source_url = self._load_source_url(cls)
            return cls(source_url=source_url)  # type: ignore[call-arg]

    @staticmethod
    def _load_source_url(cls: type) -> str:
        """Return the upstream URL to feed into a scraper constructor.

        Args:
            cls: Scraper class (or any class).

        Returns:
            The class-level ``source_url`` attribute, or a safe
            fallback when the class does not declare one.
        """
        for attr in ("source_url", "default_source_url", "URL", "url"):
            value = getattr(cls, attr, None)
            if isinstance(value, str) and value.strip():
                return value
        return "about:blank"

    @staticmethod
    def _fold(summary: OrchestratorSummary, stats: ScraperStats) -> None:
        """Fold one :class:`ScraperStats` into an :class:`OrchestratorSummary`."""
        summary.total_new += stats.inserted
        summary.total_updated += stats.updated
        summary.total_skipped += stats.skipped
        summary.total_failed += stats.failed
        summary.total_records_found += stats.records_found
        summary.total_valid += stats.valid
        summary.total_invalid += stats.invalid

    @staticmethod
    def _resolve_dry_run() -> bool:
        """Return the effective dry-run flag from the environment."""
        for candidate in ("DRY_RUN", "FIRESTORE_DRY_RUN"):
            value = os.getenv(candidate)
            if value is None:
                continue
            if value.strip().lower() in {"1", "true", "yes", "on"}:
                return True
        return False

    # ------------------------------------------------------------------
    # Console output
    # ------------------------------------------------------------------

    @staticmethod
    def _print_loading(entries: Sequence[ScraperEntry]) -> None:
        print("Loading Scrapers...")
        for entry in entries:
            print(f"  ✓ {entry.name}")
        print("Running...")

    @staticmethod
    def _print_running(entry: ScraperEntry) -> None:
        print(f"\n[{entry.name}]")

    @staticmethod
    def _print_scraper_done(stats: ScraperStats) -> None:
        """Render a single scraper block."""
        if not stats.ok:
            print(f"  Failed : {stats.error}")
            return
        print(f"  Found {stats.records_found}")
        print(f"  Valid {stats.valid}")
        print(f"  Inserted {stats.inserted}")
        print(f"  Updated {stats.updated}")
        if stats.invalid:
            print(f"  Invalid {stats.invalid}")
        if stats.skipped:
            print(f"  Skipped {stats.skipped}")
        if stats.failed:
            print(f"  Failed {stats.failed}")
        print(f"  Done ({stats.elapsed_seconds:.2f}s)")

    @staticmethod
    def _print_summary(summary: OrchestratorSummary) -> None:
        """Render the final summary block."""
        print("\nSummary")
        print("-------")
        print(f"Total Scrapers : {len(summary.scrapers)}")
        print(f"New            : {summary.total_new}")
        print(f"Updated        : {summary.total_updated}")
        print(f"Skipped        : {summary.total_skipped}")
        print(f"Failed         : {summary.total_failed}")
        print(f"Wall time      : {summary.elapsed_seconds:.2f}s")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    """Execute the orchestrator as a CLI.

    Returns:
        ``0`` when every scraper ran without failure, ``1`` otherwise.
    """
    settings = get_settings()
    configure_logging(level=settings.log_level)
    orchestrator = ScraperOrchestrator()
    summary = orchestrator.run()
    failed = sum(1 for s in summary.scrapers if not s.ok)
    return 0 if failed == 0 else 1


__all__ = [
    "ScraperStats",
    "OrchestratorSummary",
    "ScraperOrchestrator",
    "UploaderFactory",
    "main",
]


if __name__ == "__main__":  # pragma: no cover - manual CLI
    raise SystemExit(main())
