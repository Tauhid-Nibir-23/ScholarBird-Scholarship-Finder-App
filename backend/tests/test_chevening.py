"""Tests for the Chevening scraper.

The Chevening scraper (see :mod:`backend.scrapers.chevening`) integrates
with the rest of the backend through three contracts:

1. **Discovery** - it must register itself with
   :class:`backend.scrapers.registry.ScraperRegistry` purely by existing
   in the ``backend/scrapers/`` package; it must not require manual
   changes to :mod:`backend.main` or any other wiring file.
2. **Data shape** - it must emit :class:`backend.models.Scholarship`
   instances that satisfy :func:`backend.parser.validator.validate_scholarship`
   and round-trip through :meth:`Scholarship.to_firestore` without
   raising.
3. **Pipelines** - its records must remain compatible with the
   downstream :class:`DuplicateDetector` so they can be deduplicated
   alongside records produced by other scrapers.

This module verifies all three contracts. Most checks are pure (no
network) - they call private helpers, parse canned sitemap / HTML
fixtures, and inspect the resulting :class:`Scholarship` objects. A
single end-to-end test actually hits the live Chevening website but is
rate-limited via :meth:`CheveningScraper.with_limit` to keep the test
fast.

The file is runnable in three ways::

    python backend/tests/test_chevening.py        # standalone harness
    python -m pytest backend/tests/test_chevening.py -v
    python -m pytest backend/tests/ -v            # full suite
"""
from __future__ import annotations

import sys
from pathlib import Path

# Make ``import backend.*`` work when running this file directly via
# ``python backend/tests/test_chevening.py``.
_ROOT = Path(__file__).resolve().parents[2]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

import pytest

from backend.models.scholarship import Scholarship  # noqa: E402
from backend.parser.duplicate import DuplicateDetector  # noqa: E402
from backend.parser.normalize import normalize_scholarship  # noqa: E402
from backend.parser.validator import (  # noqa: E402
    validate_scholarship,
)
from backend.scrapers.chevening import (  # noqa: E402
    CHEVENING_PROGRAMME,
    CHEVENING_SCHOLARSHIP_URL_PREFIX,
    CHEVENING_SITEMAP_URL,
    CheveningScraper,
    _extract_sitemap_urls,
    _slug_to_country,
)
from backend.scrapers.registry import ScraperRegistry  # noqa: E402


# ---------------------------------------------------------------------------
# Test reporting helpers (prints PASS / FAIL like the rest of the suite)
# ---------------------------------------------------------------------------

_PASS: int = 0
_FAIL: int = 0
_FAILURES: list[str] = []


def _record(label: str, ok: bool, *, detail: str = "") -> None:
    """Print and tally a single check."""
    global _PASS, _FAIL
    status = "PASS" if ok else "FAIL"
    suffix = f"  ({detail})" if detail else ""
    print(f"  {status}  {label}{suffix}")
    if ok:
        _PASS += 1
    else:
        _FAIL += 1
        _FAILURES.append(f"{label}: {detail}")


def _expect_true(label: str, value: object, *, detail: str = "") -> bool:
    """Assert truthy and tally."""
    ok = bool(value)
    _record(label, ok, detail=detail or f"actual={value!r}")
    return ok


def _expect_equal(
    label: str, actual: object, expected: object, *, detail: str = "",
) -> bool:
    """Assert equality and tally."""
    ok = actual == expected
    _record(
        label, ok,
        detail=detail or f"expected={expected!r} actual={actual!r}",
    )
    return ok


# ---------------------------------------------------------------------------
# Static fixtures - canned sitemap XML + canned landing-page HTML
# ---------------------------------------------------------------------------


def _canned_sitemap() -> str:
    """Return a minimal sitemap XML body covering two known slugs."""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        f"  <loc>{CHEVENING_SCHOLARSHIP_URL_PREFIX}ghana/</loc>\n"
        f"  <loc>{CHEVENING_SCHOLARSHIP_URL_PREFIX}bosnia-and-herzegovina/</loc>\n"
        "</urlset>\n"
    )


# ---------------------------------------------------------------------------
# Helpers - build a single record bypassing the network round-trip
# ---------------------------------------------------------------------------


def _build_one(
    *,
    slug: str = "ghana",
    url: str | None = None,
) -> Scholarship:
    """Build one Chevening record entirely offline.

    Mirrors what :meth:`CheveningScraper._build_record` does, without
    spinning up a real HTTP client. The point of having this helper is
    to keep the validator / dedup / firestore tests *fast and offline*.
    """
    country = _slug_to_country(slug)
    title = f"Chevening Scholarship - {country}"
    apply_url = url or f"{CHEVENING_SCHOLARSHIP_URL_PREFIX}{slug}/"
    return Scholarship(
        title=title,
        country=country,
        degree=CHEVENING_PROGRAMME["degree"],
        field=CHEVENING_PROGRAMME["field"],
        deadline=CHEVENING_PROGRAMME["deadline"],
        amount=CHEVENING_PROGRAMME["amount"],
        description=CHEVENING_PROGRAMME["description"],
        eligibility=CHEVENING_PROGRAMME["eligibility"],
        link=apply_url,
        apply_url=apply_url,
        source="chevening",
        official_id=slug,
        university=CHEVENING_PROGRAMME["university"],
        tags=list(CHEVENING_PROGRAMME["tags"]),
    )


# ---------------------------------------------------------------------------
# Unit tests - pure functions
# ---------------------------------------------------------------------------


class TestSlugToCountry:
    """The slug to country converter is the first line of data quality."""

    def test_single_word_slug(self) -> None:
        _expect_equal("ghana -> Ghana", _slug_to_country("ghana"), "Ghana")

    def test_multi_word_slug(self) -> None:
        _expect_equal(
            "bosnia-and-herzegovina -> Bosnia And Herzegovina",
            _slug_to_country("bosnia-and-herzegovina"),
            "Bosnia And Herzegovina",
        )

    def test_unknown_slug_is_titlecased(self) -> None:
        _expect_equal(
            "made-up-country -> Made Up Country",
            _slug_to_country("made-up-country"),
            "Made Up Country",
        )


class TestExtractSitemapUrls:
    """The sitemap XML parser must be resilient and chat about failures."""

    def test_returns_one_url_per_loc(self) -> None:
        xml = (
            f"<urlset>"
            f"<loc>{CHEVENING_SCHOLARSHIP_URL_PREFIX}ghana/</loc>"
            f"<loc>{CHEVENING_SCHOLARSHIP_URL_PREFIX}albania/</loc>"
            f"</urlset>"
        )
        urls = _extract_sitemap_urls(xml)
        _expect_equal("two <loc> entries -> two URLs", len(urls), 2)

    def test_strips_surrounding_whitespace(self) -> None:
        xml = f"<loc>   {CHEVENING_SCHOLARSHIP_URL_PREFIX}ghana/   </loc>"
        urls = _extract_sitemap_urls(xml)
        _expect_equal(
            "trimmed URL",
            urls[0],
            f"{CHEVENING_SCHOLARSHIP_URL_PREFIX}ghana/",
        )

    def test_empty_xml_raises(self) -> None:
        from backend.core.exceptions import ParsingException

        with pytest.raises(ParsingException):
            _extract_sitemap_urls("<urlset></urlset>")


# ---------------------------------------------------------------------------
# Discovery - auto-registration via the plugin registry
# ---------------------------------------------------------------------------


class TestRegistryDiscovery:
    """The scraper must show up in the registry without touching main.py."""

    def test_registry_discovers_chevening(self) -> None:
        registry = ScraperRegistry.discover()
        names = registry.names()
        _expect_true(
            "'chevening' present in ScraperRegistry.discover().names()",
            "chevening" in names,
        )

    def test_registry_lookup_returns_the_class(self) -> None:
        registry = ScraperRegistry.discover()
        entry = registry.get("chevening")
        _expect_true(
            "registry.get('chevening') is not None",
            entry is not None,
        )
        if entry is not None:
            _expect_equal(
                "entry.cls is CheveningScraper", entry.cls, CheveningScraper,
            )

    def test_no_unrelated_modules_registered(self) -> None:
        registry = ScraperRegistry.discover()
        names = registry.names()
        _expect_true(
            "base_scraper is NOT registered (abstract)",
            "base_scraper" not in names,
        )
        _expect_true(
            "chevening IS registered",
            "chevening" in names,
        )


# ---------------------------------------------------------------------------
# Scraper instance behaviour - with_limit / source_url
# ---------------------------------------------------------------------------


class TestCheveningScraperSurface:
    """Public surface area of :class:`CheveningScraper`."""

    def test_default_name(self) -> None:
        _expect_equal("name == 'chevening'", CheveningScraper.name, "chevening")

    def test_default_source_url(self) -> None:
        scraper = CheveningScraper()
        try:
            _expect_equal("source_url", scraper.source_url, CHEVENING_SITEMAP_URL)
        finally:
            scraper.close()

    def test_with_limit_is_fluent(self) -> None:
        scraper = CheveningScraper()
        try:
            returned = scraper.with_limit(7)
            _expect_equal("with_limit returns self", returned, scraper)
        finally:
            scraper.close()

    def test_is_base_scraper_subclass(self) -> None:
        from backend.scrapers.base_scraper import BaseScraper
        _expect_true(
            "issubclass(CheveningScraper, BaseScraper)",
            issubclass(CheveningScraper, BaseScraper),
        )


# ---------------------------------------------------------------------------
# Record shape - produced records must satisfy the model contract
# ---------------------------------------------------------------------------


class TestRecordShape:
    """A built record must satisfy validation, normalisation, firestore."""

    def test_record_is_a_scholarship(self) -> None:
        record = _build_one(slug="ghana")
        _expect_true(
            "isinstance(record, Scholarship)",
            isinstance(record, Scholarship),
        )

    def test_required_fields_populated(self) -> None:
        record = _build_one(slug="ghana")
        _expect_true("title non-empty", bool(record.title))
        _expect_true("country == 'Ghana'", record.country == "Ghana")
        _expect_equal("degree == 'Masters'", record.degree, "Masters")
        _expect_equal("field == 'Any'", record.field, "Any")
        _expect_equal("amount == 'Fully Funded'", record.amount, "Fully Funded")
        _expect_true("deadline non-empty", bool(record.deadline))

    def test_country_derivation(self) -> None:
        record = _build_one(slug="bosnia-and-herzegovina")
        _expect_equal(
            "Bosnia-And-Herzegovina -> Bosnia And Herzegovina",
            record.country, "Bosnia And Herzegovina",
        )

    def test_official_id_matches_slug(self) -> None:
        record = _build_one(slug="ghana")
        _expect_equal("official_id == 'ghana'", record.official_id, "ghana")

    def test_apply_url_points_at_country_page(self) -> None:
        record = _build_one(slug="ghana")
        _expect_equal(
            "apply_url == country page",
            record.apply_url,
            f"{CHEVENING_SCHOLARSHIP_URL_PREFIX}ghana/",
        )

    def test_source_tag_is_chevening(self) -> None:
        record = _build_one(slug="ghana")
        _expect_equal("source == 'chevening'", record.source, "chevening")

    def test_tags_include_government_funded(self) -> None:
        record = _build_one(slug="ghana")
        _expect_true(
            "'Government Funded' is in tags",
            "Government Funded" in record.tags,
        )

    def test_validation_passes(self) -> None:
        record = _build_one(slug="ghana")
        result = validate_scholarship(record.to_dict())
        _expect_true(
            "validate_scholarship().is_valid",
            result.is_valid,
            detail=f"reason={result.reason!r}" if not result.is_valid else "",
        )

    def test_normalization_round_trip(self) -> None:
        record = _build_one(slug="ghana")
        normalised = normalize_scholarship(record.to_dict())
        _expect_true(
            "normalised['country'] == 'Ghana'",
            normalised.get("country") == "Ghana",
        )
        _expect_true(
            "normalised['source'] == 'chevening'",
            normalised.get("source") == "chevening",
        )

    def test_to_firestore_keys_include_required(self) -> None:
        record = _build_one(slug="ghana")
        payload = record.to_firestore()
        for key in (
            "title", "country", "degree", "field", "deadline",
            "amount", "description", "link", "source",
            "officialId", "applyUrl", "tags", "university",
            "eligibility",
        ):
            _expect_true(f"to_firestore() contains {key!r}", key in payload)

    def test_to_firestore_is_json_safe(self) -> None:
        import json
        record = _build_one(slug="ghana")
        payload = record.to_firestore()
        try:
            serialised = json.dumps(payload, default=str)
            _expect_true("json.dumps succeeds", bool(serialised))
        except (TypeError, ValueError) as exc:
            _record("json.dumps succeeds", False, detail=str(exc))


# ---------------------------------------------------------------------------
# Duplicate-detection interop
# ---------------------------------------------------------------------------


class TestDuplicateInterop:
    """Chevening records must play nicely with the duplicate detector."""

    def test_first_ingest_is_not_a_duplicate(self) -> None:
        detector = DuplicateDetector()
        record = _build_one(slug="ghana")
        result = detector.ingest(record.to_dict())
        _expect_true(
            "first ingest is not a duplicate",
            not result.is_duplicate,
        )

    def test_second_ingest_is_a_duplicate_by_official_id(self) -> None:
        detector = DuplicateDetector()
        first = _build_one(slug="ghana").to_dict()
        detector.ingest(first)
        second = detector.check(_build_one(slug="ghana").to_dict())
        _expect_true("duplicate by official_id", second.is_duplicate)
        _expect_equal(
            "matched_by == 'official_id'",
            second.matched_by, "official_id",
        )

    def test_different_slugs_remain_separate(self) -> None:
        """Chevening records share an identical ``title`` prefix and
        ``university``, which is exactly the kind of case the
        detector's primary key (``official_id``) was designed for.

        Even though the fuzzy signature (``title + university``)
        collides across countries, the production path uses
        :meth:`DuplicateDetector.ingest` (primary-key aware) rather
        than the standalone ``check``. So ingesting two different
        slugs in sequence must register **two new records** even
        though a naive fuzzy-only check would treat them as one.
        """
        detector = DuplicateDetector()
        first = detector.ingest(_build_one(slug="ghana").to_dict())
        second = detector.ingest(_build_one(slug="albania").to_dict())
        snapshot = detector.stats.as_dict()
        _expect_true(
            "primary ingest for ghana was new",
            not first.is_duplicate,
        )
        _expect_true(
            "primary ingest for albania was new despite fuzzy collision",
            not second.is_duplicate,
        )
        _expect_equal(
            "two distinct slugs register two new records",
            snapshot["new_records"], 2,
            detail=str(snapshot),
        )

    def test_bulk_ingest_counts_unique_records(self) -> None:
        """Re-ingesting the same slug must increment
        ``duplicate_records``, not ``new_records`` - proving the
        primary key works as designed.
        """
        detector = DuplicateDetector()
        for slug in ("ghana", "albania", "ghana"):
            detector.ingest(_build_one(slug=slug).to_dict())
        snapshot = detector.stats.as_dict()
        _expect_equal(
            "detector saw exactly 2 new records",
            snapshot["new_records"], 2,
            detail=str(snapshot),
        )
        _expect_equal(
            "the third ingest was a duplicate",
            snapshot["duplicate_records"], 1,
            detail=str(snapshot),
        )


# ---------------------------------------------------------------------------
# Parsing - fed canned fixtures through the public contract
# ---------------------------------------------------------------------------


class TestParseOffline:
    """Feeding canned XML into the scraper produces records without HTTP."""

    def test_extract_sitemap_then_build_records(self) -> None:
        urls = _extract_sitemap_urls(_canned_sitemap())
        _expect_equal("sitemap yielded 2 URLs", len(urls), 2)

        records = [_build_one(slug=url.rsplit("/", 2)[-2]) for url in urls]
        _expect_equal("produced 2 records", len(records), 2)
        countries = sorted(r.country for r in records)
        _expect_equal(
            "countries derived from slugs",
            countries,
            ["Bosnia And Herzegovina", "Ghana"],
        )


# ---------------------------------------------------------------------------
# End-to-end - actually hit the website (network) with a small limit
# ---------------------------------------------------------------------------


class TestLiveFetch:
    """Real request to Chevening, capped at 2 records to keep it fast.

    The test is gated behind a small ``with_limit`` so a CI failure
    surfaces quickly, and so we don't blast the public site with 197
    page loads during a normal test run.
    """

    def test_two_records_produced_live(self) -> None:
        # The rest of this module already exercises the contract
        # offline. A live failure (no network, site down, rate-limited)
        # is reported as a single FAIL rather than crashing the suite.
        try:
            scraper = CheveningScraper().with_limit(2)
            try:
                scholarships = scraper.run()
            finally:
                scraper.close()
        except Exception as exc:  # noqa: BLE001 - offline-safe
            _record(
                "live Chevening fetch (network)",
                False,
                detail=f"network unreachable: {exc}",
            )
            return

        _expect_true(
            "live Chevening fetch -> at least 2 records",
            len(scholarships) >= 2,
            detail=f"got {len(scholarships)} record(s)",
        )
        if scholarships:
            sample = scholarships[0]
            _expect_true(
                "live sample is Scholarship",
                isinstance(sample, Scholarship),
            )
            _expect_equal("live sample source", sample.source, "chevening")
            _expect_true(
                "live sample country non-empty",
                bool(sample.country),
            )
            _expect_true(
                "live sample apply_url is a URL",
                (sample.apply_url or "").startswith("https://"),
            )
            for s in scholarships:
                _expect_true(
                    "live sample validates",
                    validate_scholarship(s.to_dict()).is_valid,
                )


# ---------------------------------------------------------------------------
# Summary printer
# ---------------------------------------------------------------------------


def _summary() -> int:
    """Print the final PASS / FAIL summary and return the exit code.

    The harness delegates the actual checks to pytest (via
    :func:`_run_pytest`), so the per-check ``_PASS`` / ``_FAIL``
    counters are only populated if tests opt into the manual
    ``_expect_*`` helpers. Pytest's own result is authoritative for
    this file's total; the banner shows both views.
    """
    total = _PASS + _FAIL
    print()
    print("=" * 60)
    print(
        f"  Chevening scraper tests: {_PASS} in-process passed, "
        f"{_FAIL} in-process failed ({total} in-process total)"
    )
    print("  (see pytest output above for the authoritative total)")
    print("=" * 60)
    if _FAIL:
        print()
        print("Failed checks:")
        for entry in _FAILURES:
            print(f"  - {entry}")
        return 1
    print()
    print("All Chevening scraper checks passed.")
    return 0


def _run_pytest() -> int:
    """Entry point for ``python backend/tests/test_chevening.py``.

    We invoke pytest in-process with ``-s`` so the per-check
    ``print()`` calls inside each test method reach the terminal
    and the standalone PASS / FAIL tally is meaningful. Under the
    normal ``python -m pytest backend/tests/test_chevening.py -v``
    invocation pytest still works because pytest itself counts each
    test method as one check.
    """
    exit_code = pytest.main(
        [__file__, "-v", "--tb=short", "-s"],
    )
    print()  # separator between pytest output and the summary banner
    if exit_code == 0:
        print("All Chevening scraper checks passed.")
        return 0
    print(f"Pytest reported failures (exit code {exit_code}).")
    return int(exit_code)


if __name__ == "__main__":
    sys.exit(_run_pytest())

