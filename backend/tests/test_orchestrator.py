"""Tests for the plugin-based scraper orchestrator.

These tests exercise:

* :class:`backend.scrapers.registry.ScraperRegistry` discovery,
  registration, and lookup.
* :class:`backend.orchestrator.ScraperOrchestrator` sequential mode.
* :class:`backend.orchestrator.ScraperOrchestrator` parallel mode.
* Per-scraper failure isolation.
* Statistics aggregation and the
  :class:`backend.orchestrator.OrchestratorSummary` dataclass.

The tests are offline — no HTTP, no Firebase. Scraper behaviour is
provided by lightweight fake :class:`BaseScraper` subclasses that
produce deterministic :class:`Scholarship` records, and the
:class:`FirestoreUploader` is replaced with a fake that records
``upsert_many`` calls.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Make the project root importable when running this file directly via
# ``python backend/tests/test_orchestrator.py``.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

import pytest

from backend.config.settings import Settings
from backend.firebase import UploadSummary
from backend.models.scholarship import Scholarship
from backend.orchestrator import (
    OrchestratorSummary,
    ScraperOrchestrator,
    ScraperStats,
)
from backend.parser.duplicate import DuplicateDetector
from backend.scrapers.base_scraper import BaseScraper
from backend.scrapers.registry import ScraperEntry, ScraperRegistry


# ---------------------------------------------------------------------------
# Fake scrapers
# ---------------------------------------------------------------------------


class _FakeScraper(BaseScraper):
    """Deterministic scraper that yields ``build_records``.

    Subclasses override :attr:`records` to produce a fixed list of
    :class:`Scholarship` records. The ``fetch`` / ``parse`` contract is
    bypassed by overriding :meth:`run` directly so the tests stay
    network-free.
    """

    name: str = "fake"
    records: List[Scholarship] = []

    def __init__(self) -> None:  # type: ignore[no-super-call]
        # Deliberately skip BaseScraper.__init__ — the tests do not
        # need an HTTP client or settings singleton.
        self._closed = False

    def fetch(self) -> str:  # type: ignore[override]
        """Return an empty payload — tests call :meth:`run` directly."""
        return ""

    def parse(self, raw_content: str) -> List[Scholarship]:  # type: ignore[override]
        """Return the static records list (mirrors ``run``)."""
        return list(self.records)

    def run(self) -> List[Scholarship]:  # type: ignore[override]
        return list(self.records)

    def close(self) -> None:  # pragma: no cover - trivial
        self._closed = True

    def __enter__(self) -> "_FakeScraper":  # type: ignore[override]
        return self

    def __exit__(self, *exc: Any) -> None:  # type: ignore[override]
        self.close()


def _make_scholarship(
    title: str,
    *,
    country: str = "Germany",
    degree: str = "Masters",
    field: str = "Engineering",
    deadline: str = "2026-12-31",
    source: str = "fake",
    link: str = "https://example.com/scholarship",
    apply_url: Optional[str] = None,
    official_id: Optional[str] = None,
) -> Scholarship:
    """Build a fully-populated :class:`Scholarship` for tests."""
    return Scholarship(
        title=title,
        country=country,
        degree=degree,
        field=field,
        deadline=deadline,
        amount="Fully Funded",
        description=f"Test description for {title}",
        link=link,
        apply_url=apply_url or link,
        source=source,
        official_id=official_id,
    )


class _HappyScraper(_FakeScraper):
    name = "happy"
    # Distinct titles / countries / fields / links so the detector's
    # fuzzy pass does not collapse these into a single record.
    records = [
        _make_scholarship(
            "DAAD Computer Science Scholarship",
            country="Germany",
            field="Computer Science",
            link="https://example.com/daad-cs",
            official_id="happy-cs",
        ),
        _make_scholarship(
            "Chevening Public Administration Grant",
            country="United Kingdom",
            field="Public Administration",
            link="https://example.com/chevening-pa",
            official_id="happy-pa",
        ),
    ]


class _OtherScraper(_FakeScraper):
    name = "other"
    records = [
        _make_scholarship(
            "Fulbright Mechanical Engineering Fellowship",
            country="United States",
            field="Mechanical Engineering",
            link="https://example.com/fulbright-me",
            official_id="other-me",
        ),
    ]


class _EmptyScraper(_FakeScraper):
    name = "empty"
    records = []


class _BrokenScraper(_FakeScraper):
    """A scraper whose ``run()`` method raises."""

    name = "broken"

    def run(self) -> List[Scholarship]:  # type: ignore[override]
        raise RuntimeError("scraper kaboom")


class _InvalidScraper(_FakeScraper):
    """A scraper whose records will fail validation."""

    name = "invalid"

    def __init__(self) -> None:  # type: ignore[no-super-call]
        self._closed = False
        # Country is empty — fails the non-empty check in the validator.
        self.records = [
            _make_scholarship("Broken Country", country=""),
            _make_scholarship("Broken Link", link="not-a-url"),
        ]


# ---------------------------------------------------------------------------
# Fake uploader
# ---------------------------------------------------------------------------


class _FakeUploader:
    """Stand-in for :class:`FirestoreUploader` that records payloads.

    The orchestrator already pre-deduplicates records via
    :meth:`DuplicateDetector.ingest` before calling
    :meth:`upsert_many`. Every record the orchestrator hands us is
    therefore treated as new for accounting purposes; we just record
    the batch and remember the hashes so a second run within the same
    process can detect repeats.
    """

    def __init__(self, detector: DuplicateDetector) -> None:
        self.detector = detector
        self.batches: List[List[Scholarship]] = []
        self.dry_run = False

    def upsert_many(self, records: Any) -> UploadSummary:
        """Record every batch and return a deterministic summary."""
        batch = list(records)
        self.batches.append(batch)
        summary = UploadSummary(dry_run=self.dry_run)
        for record in batch:
            # Remember the hash so a second ``upsert_many`` call on the
            # same detector would correctly treat these as duplicates.
            self.detector.remember(record.to_dict())
            summary.new += 1
        summary.batch_count = 1
        return summary


def _fake_uploader_factory(
    detector: DuplicateDetector,
) -> _FakeUploader:
    """Build a :class:`FakeUploader` for the given detector."""
    return _FakeUploader(detector)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_registry() -> ScraperRegistry:
    """Registry pre-loaded with fake scrapers (no filesystem walk)."""
    registry = ScraperRegistry()
    registry.register(_HappyScraper)
    registry.register(_OtherScraper)
    registry.register(_EmptyScraper)
    registry.register(_InvalidScraper)
    return registry


def _settings(
    *,
    parallel: bool = False,
    workers: int = 3,
    enabled: Tuple[str, ...] = (),
    log_level: str = "WARNING",
) -> Settings:
    """Build a :class:`Settings` instance with the orchestrator fields set."""
    return Settings(
        env="test",
        log_level=log_level,
        firebase_credentials_path=None,
        scraper_user_agent="ScholarBirdBot/test",
        scraper_request_timeout=30,
        enable_parallel=parallel,
        max_workers=workers,
        enabled_scrapers=enabled,
    )


# ---------------------------------------------------------------------------
# Registry tests
# ---------------------------------------------------------------------------


class TestScraperRegistry:
    """Behaviour of :class:`ScraperRegistry`."""

    def test_register_with_class(self) -> None:
        registry = ScraperRegistry()
        entry = registry.register(_HappyScraper)
        assert entry.name == "happy"
        assert entry.cls is _HappyScraper

    def test_register_with_instance(self) -> None:
        registry = ScraperRegistry()
        scraper = _HappyScraper()
        entry = registry.register(scraper)
        assert entry.cls is _HappyScraper
        assert registry.get("happy") is not None

    def test_register_abstract_raises(self) -> None:
        registry = ScraperRegistry()
        with pytest.raises(TypeError):
            registry.register(BaseScraper)

    def test_register_non_subclass_raises(self) -> None:
        registry = ScraperRegistry()
        with pytest.raises(TypeError):
            registry.register(int)

    def test_unregister_by_name(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        removed = registry.unregister("happy")
        assert removed is not None
        assert "happy" not in registry

    def test_unregister_by_class(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        assert registry.unregister(_HappyScraper) is not None
        assert "happy" not in registry

    def test_unregister_missing_returns_none(self) -> None:
        registry = ScraperRegistry()
        assert registry.unregister("missing") is None
        assert registry.unregister(_HappyScraper) is None

    def test_list_is_sorted(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_OtherScraper)
        registry.register(_EmptyScraper)
        names = [entry.name for entry in registry.list()]
        assert names == sorted(names)

    def test_names_returns_sorted_strings(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_OtherScraper)
        assert registry.names() == ["happy", "other"]

    def test_len_and_contains(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        assert len(registry) == 1
        assert "happy" in registry
        assert "missing" not in registry

    def test_iter_yields_entries(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_OtherScraper)
        assert [e.name for e in registry] == ["happy", "other"]

    def test_get_returns_entry_or_none(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        assert registry.get("happy") is not None
        assert registry.get("other") is None

    def test_register_is_idempotent(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_HappyScraper)
        assert len(registry) == 1

    def test_discover_excludes_underscore_modules(self) -> None:
        registry = ScraperRegistry.discover()
        # The package only contains ``daad`` and ``base_scraper``;
        # ``base_scraper`` is abstract and must not be registered.
        names = registry.names()
        assert "base_scraper" not in names
        assert "daad" in names


# ---------------------------------------------------------------------------
# Orchestrator tests — sequential mode
# ---------------------------------------------------------------------------


class TestSequentialOrchestrator:
    """Sequential execution of the orchestrator."""

    def test_runs_every_registered_scraper(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        names = [stats.name for stats in summary.scrapers]
        assert "happy" in names
        assert "other" in names
        assert "empty" in names
        assert "invalid" in names

    def test_happy_scraper_counts_inserts(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        happy = next(s for s in summary.scrapers if s.name == "happy")
        assert happy.ok is True
        assert happy.records_found == 2
        assert happy.valid == 2
        assert happy.invalid == 0
        assert happy.inserted == 2
        assert happy.error is None

    def test_invalid_records_are_counted(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        invalid = next(s for s in summary.scrapers if s.name == "invalid")
        assert invalid.records_found == 2
        assert invalid.invalid == 2
        assert invalid.valid == 0
        assert invalid.inserted == 0

    def test_empty_scraper_runs_clean(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        empty = next(s for s in summary.scrapers if s.name == "empty")
        assert empty.ok is True
        assert empty.records_found == 0
        assert empty.inserted == 0

    def test_enabled_scrapers_filter(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False, enabled=("happy",)),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        names = [s.name for s in summary.scrapers]
        assert names == ["happy"]

    def test_enabled_scrapers_with_missing_name_warns(
        self,
        fake_registry: ScraperRegistry,
        caplog: pytest.LogCaptureFixture,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(
                parallel=False,
                enabled=("happy", "ghost"),
            ),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
            log_level="WARNING",
        )
        with caplog.at_level("WARNING"):
            orchestrator.run()
        assert any("ghost" in record.message for record in caplog.records)

    def test_summary_aggregates_totals(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        # 2 happy + 1 other = 3 inserted; 0 invalid records uploaded.
        assert summary.total_new == 3
        assert summary.total_records_found == 5
        assert summary.total_valid == 3
        assert summary.total_invalid == 2
        assert summary.parallel is False

    def test_summary_has_wall_time(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        orchestrator = ScraperOrchestrator(
            registry=fake_registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        assert summary.elapsed_seconds >= 0.0

    def test_dedupes_within_run(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        """Two scrapers producing the same record → only one insert."""
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_OtherScraper)
        # Inject a duplicate of the first ``happy`` record into
        # ``other`` so the detector should flag it as a duplicate
        # (matched by ``official_id``) inside whichever scraper runs
        # second.
        other_records_original = list(_OtherScraper.records)
        _OtherScraper.records = list(_HappyScraper.records[:1]) + list(
            _OtherScraper.records,
        )
        try:
            orchestrator = ScraperOrchestrator(
                registry=registry,
                settings=_settings(parallel=False),
                dry_run=True,
                uploader_factory=_fake_uploader_factory,
            )
            summary = orchestrator.run()
        finally:
            _OtherScraper.records = other_records_original
        # Happy contributes 2 distinct records, ``other`` contributes
        # 1 new record; the duplicated happy record is skipped.
        assert summary.total_new == 3
        assert summary.total_skipped >= 1


# ---------------------------------------------------------------------------
# Orchestrator tests — failure isolation
# ---------------------------------------------------------------------------


class TestFailureIsolation:
    """A broken scraper must not abort the run."""

    def test_broken_scraper_marks_error(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_BrokenScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        broken = next(s for s in summary.scrapers if s.name == "broken")
        assert broken.ok is False
        assert broken.error is not None
        assert "kaboom" in broken.error

    def test_broken_scraper_does_not_stop_others(
        self,
        fake_registry: ScraperRegistry,
    ) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_BrokenScraper)
        registry.register(_OtherScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        names = [s.name for s in summary.scrapers]
        assert set(names) == {"happy", "broken", "other"}
        # The healthy scrapers still ran to completion.
        happy = next(s for s in summary.scrapers if s.name == "happy")
        other = next(s for s in summary.scrapers if s.name == "other")
        assert happy.ok is True
        assert other.ok is True
        assert happy.inserted == 2
        assert other.inserted == 1


# ---------------------------------------------------------------------------
# Orchestrator tests — parallel mode
# ---------------------------------------------------------------------------


class TestParallelOrchestrator:
    """Parallel execution via :class:`ThreadPoolExecutor`."""

    def test_parallel_dispatches_all_scrapers(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_OtherScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=True, workers=2),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        assert summary.parallel is True
        assert summary.max_workers == 2
        assert {s.name for s in summary.scrapers} == {"happy", "other"}
        assert summary.total_new == 3

    def test_parallel_with_workers_one_degrades_to_sequential(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=True, workers=1),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        # Parallel flag is set but only one worker runs — the consumer
        # still gets a deterministic sequential result.
        assert summary.parallel is True
        assert summary.max_workers == 1
        assert len(summary.scrapers) == 1

    def test_parallel_failure_isolation(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        registry.register(_BrokenScraper)
        registry.register(_OtherScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=True, workers=3),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        broken = next(s for s in summary.scrapers if s.name == "broken")
        assert broken.ok is False
        for healthy in ("happy", "other"):
            stats = next(s for s in summary.scrapers if s.name == healthy)
            assert stats.ok is True


# ---------------------------------------------------------------------------
# Orchestrator tests — empty registry
# ---------------------------------------------------------------------------


class TestEmptyRegistry:
    """No scrapers registered → empty summary, no crash."""

    def test_empty_registry_returns_empty_summary(self) -> None:
        registry = ScraperRegistry()
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        summary = orchestrator.run()
        assert isinstance(summary, OrchestratorSummary)
        assert summary.scrapers == []
        assert summary.total_new == 0
        assert summary.total_records_found == 0


# ---------------------------------------------------------------------------
# Dataclass tests
# ---------------------------------------------------------------------------


class TestDataclasses:
    """Sanity checks for the public dataclasses."""

    def test_scraper_stats_ok_property(self) -> None:
        stats_ok = ScraperStats(name="ok")
        stats_fail = ScraperStats(name="fail", error="boom")
        assert stats_ok.ok is True
        assert stats_fail.ok is False

    def test_scraper_stats_as_dict(self) -> None:
        stats = ScraperStats(name="x", records_found=10, inserted=5)
        snapshot = stats.as_dict()
        assert snapshot["name"] == "x"
        assert snapshot["records_found"] == 10
        assert snapshot["inserted"] == 5
        assert snapshot["error"] is None

    def test_orchestrator_summary_as_dict(self) -> None:
        summary = OrchestratorSummary()
        snapshot = summary.as_dict()
        assert snapshot["total_scrapers"] == 0
        assert snapshot["parallel"] is False
        assert snapshot["scrapers"] == []


# ---------------------------------------------------------------------------
# ScraperEntry
# ---------------------------------------------------------------------------


class TestScraperEntry:
    """Coverage for the small :class:`ScraperEntry` dataclass."""

    def test_is_frozen(self) -> None:
        entry = ScraperEntry(name="x", cls=_HappyScraper, module="test")
        with pytest.raises(Exception):
            entry.name = "y"  # type: ignore[misc]

    def test_str_repr_contains_name(self) -> None:
        entry = ScraperEntry(name="x", cls=_HappyScraper, module="test")
        assert "x" in str(entry)


# ---------------------------------------------------------------------------
# Wall-clock sanity check
# ---------------------------------------------------------------------------


class TestPerformance:
    """Light non-flaky performance smoke test."""

    def test_wall_time_within_budget(self) -> None:
        registry = ScraperRegistry()
        registry.register(_HappyScraper)
        orchestrator = ScraperOrchestrator(
            registry=registry,
            settings=_settings(parallel=False),
            dry_run=True,
            uploader_factory=_fake_uploader_factory,
        )
        started = time.perf_counter()
        orchestrator.run()
        elapsed = time.perf_counter() - started
        # Generous bound: 5 seconds for two fake records. Anything
        # slower points at a real regression.
        assert elapsed < 5.0, f"Orchestrator took {elapsed:.2f}s"
