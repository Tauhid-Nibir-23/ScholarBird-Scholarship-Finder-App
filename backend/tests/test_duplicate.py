"""Smoke tests for the duplicate-detection engine.

The harness mirrors :mod:`backend.tests.test_normalization` — every
section banner prints a ``PASS`` / ``FAIL`` line for each check and the
script returns ``0`` only when every check passes. The script is
runnable as ``python backend/tests/test_duplicate.py``.

Sections covered (30+ checks):

* pure helpers (``generate_content_hash``, ``build_duplicate_key``)
* primary lookup (``official_id``, ``apply_url``, content hash)
* fuzzy lookup (90% / 89% / different university / missing fields)
* statistics counters
* Scholarship model delegation
* bulk-load + reset behaviour
* performance gate (10k index with sub-second check)
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

# Make ``python backend/tests/test_duplicate.py`` work without
# requiring the user to set ``PYTHONPATH``.
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.models.scholarship import Scholarship
from backend.parser.duplicate import (  # noqa: E402
    DuplicateDetector,
    DuplicateResult,
    DuplicateStats,
    build_duplicate_key,
    generate_content_hash,
)


_PASS: int = 0
_FAIL: int = 0
_FAILURES: list[str] = []


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
        _FAILURES.append(f"{label}: expected={expected!r} actual={actual!r}")


def expect_true(label: str, actual: object) -> None:
    """Tally a boolean expectation."""
    expect(label, bool(actual), True)


def expect_false(label: str, actual: object) -> None:
    """Tally a boolean expectation."""
    expect(label, bool(actual), False)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def baseline_record(**overrides: object) -> dict:
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
    }
    base.update(overrides)
    return base


# ---------------------------------------------------------------------------
# Section 1 — pure helpers
# ---------------------------------------------------------------------------

def test_pure_helpers() -> None:
    banner("Pure helpers")

    # generate_content_hash
    h1 = generate_content_hash(baseline_record())
    h2 = generate_content_hash(baseline_record())
    expect("hash is deterministic", h1 == h2, True)
    expect_true("hash is 64 chars", len(h1) == 64)

    # Case + whitespace insensitivity
    h_upper = generate_content_hash(baseline_record(title="FULBRIGHT   FOREIGN  Student Programme"))
    expect("hash case/whitespace insensitive", h_upper, h1)

    # Country change → new hash
    h_diff_country = generate_content_hash(baseline_record(country="Germany"))
    expect_true("country change breaks hash", h_diff_country != h1)

    # build_duplicate_key priority
    expect("key uses official_id first", build_duplicate_key(baseline_record()),
           "official_id::ft-001")
    expect("key falls back to apply_url",
           build_duplicate_key(baseline_record(official_id=None)),
           "apply_url::https://apply.example.com/fulbright")
    expect("key returns None when both missing",
           build_duplicate_key(baseline_record(official_id=None, apply_url=None)),
           None)
    expect("key ignores empty official_id",
           build_duplicate_key(baseline_record(official_id="")),
           "apply_url::https://apply.example.com/fulbright")
    expect("key ignores whitespace official_id",
           build_duplicate_key(baseline_record(official_id="   ")),
           "apply_url::https://apply.example.com/fulbright")


# ---------------------------------------------------------------------------
# Section 2 — primary lookup
# ---------------------------------------------------------------------------

def test_primary_lookup() -> None:
    banner("Primary lookup (official_id / apply_url / content_hash)")

    detector = DuplicateDetector()
    record = baseline_record()

    # First time → not a duplicate.
    first = detector.check(record)
    expect_false("baseline not duplicate yet", first.is_duplicate)
    expect("baseline matched_by none", first.matched_by, "none")

    # Index it, then check again.
    detector.remember(record)
    second = detector.check(record)
    expect_true("remember then check → duplicate", second.is_duplicate)
    expect("duplicate matched_by official_id", second.matched_by, "official_id")
    expect("duplicate confidence == 1.0", second.confidence, 1.0)

    # Same apply_url, different title (so content hash misses).
    apply_only = baseline_record(
        official_id=None,
        title="Fulbright Foreign Student Programme (variant)",
        apply_url="https://apply.example.com/fulbright",
    )
    third = detector.check(apply_only)
    expect_true("apply_url hit when official_id missing",
                third.is_duplicate)
    expect("matched_by apply_url", third.matched_by, "apply_url")

    # No primary keys at all → falls through to content hash.
    no_id = baseline_record(official_id=None, apply_url=None)
    fourth = detector.check(no_id)
    expect_true("content_hash hit when primary missing",
                fourth.is_duplicate)
    expect("matched_by content_hash", fourth.matched_by, "content_hash")

    # Different scholarship → not a duplicate.
    different = baseline_record(title="Chevening Scholarship",
                                official_id="chv-002",
                                apply_url="https://apply.example.com/chevening")
    expect_false("different scholarship not duplicate",
                 detector.check(different).is_duplicate)


# ---------------------------------------------------------------------------
# Section 3 — fuzzy lookup
# ---------------------------------------------------------------------------

def test_fuzzy_lookup() -> None:
    banner("Fuzzy lookup (RapidFuzz ≥ 90%)")

    detector = DuplicateDetector()
    original = baseline_record(
        official_id=None,
        apply_url=None,
        title="Rhodes Scholarship for African Students",
        university="University of Oxford",
    )
    detector.remember(original)

    # 95% similar title (small spelling tweak).
    similar_95 = baseline_record(
        official_id=None,
        apply_url=None,
        title="Rhodes Scholarship for African Students.",
        university="University of Oxford",
    )
    result_95 = detector.check(similar_95)
    expect_true("95% similar title flagged", result_95.is_duplicate)
    expect("fuzzy matched_by", result_95.matched_by, "fuzzy")

    # 85% similar title (one key phrase dropped, university matches).
    similar_below = baseline_record(
        official_id=None,
        apply_url=None,
        title="Rhodes Trust Programme",
        university="University of Oxford",
    )
    result_below = detector.check(similar_below)
    expect_false("sub-90% similar title accepted",
                 result_below.is_duplicate)

    # Same title, different university → not duplicate.
    diff_uni = baseline_record(
        official_id=None,
        apply_url=None,
        title="Rhodes Scholarship for African Students",
        university="Harvard University",
    )
    expect_false("different university not duplicate",
                 detector.check(diff_uni).is_duplicate)

    # Completely different title.
    diff_title = baseline_record(
        official_id=None,
        apply_url=None,
        title="Erasmus Mundus Masters Scholarship",
        university="Various European universities",
    )
    expect_false("completely different title accepted",
                 detector.check(diff_title).is_duplicate)

    # Fuzzy candidate cap respected when threshold lowered.
    permissive = DuplicateDetector(fuzzy_threshold=50)
    permissive.remember(baseline_record(
        official_id=None,
        apply_url=None,
        title="A B C D E F G H I J K L M N O P",
        university="University of Testing",
    ))
    result_perm = permissive.check(baseline_record(
        official_id=None,
        apply_url=None,
        title="A B C D E F G H I J K L M N X Y Z",
        university="University of Testing",
    ))
    expect_true("permissive threshold triggers match",
                result_perm.is_duplicate)

    # Missing title → fuzzy stage skipped.
    expect_false("missing title skipped by fuzzy",
                 detector.check({"title": "", "country": "X",
                                 "degree": "Masters", "field": "Y",
                                 "deadline": "2026-01-01",
                                 "amount": "", "description": "",
                                 "link": "https://x", "source": "x",
                                 "university": None}).is_duplicate)


# ---------------------------------------------------------------------------
# Section 4 — statistics
# ---------------------------------------------------------------------------

def test_statistics() -> None:
    banner("Statistics counters")

    detector = DuplicateDetector()
    record_a = baseline_record()
    record_b = baseline_record(
        title="Chevening Scholarship",
        official_id="chv-100",
        apply_url="https://apply.example.com/chevening",
    )

    detector.ingest(record_a)
    expect("new_records +1", detector.stats.new_records, 1)
    expect("duplicate_records 0", detector.stats.duplicate_records, 0)

    detector.ingest(record_b)
    expect("new_records +2", detector.stats.new_records, 2)

    # Re-ingest record_a → duplicate counter.
    detector.ingest(record_a)
    expect("duplicate_records +1",
           detector.stats.duplicate_records, 1)
    expect("new_records unchanged",
           detector.stats.new_records, 2)

    # mark_updated flow.
    detector.ingest(record_a, mark_updated=True)
    expect("updated_records +1",
           detector.stats.updated_records, 1)
    expect("new_records still 2",
           detector.stats.new_records, 2)

    # mark_ignored flow.
    detector.ingest(baseline_record(title="XYZ"), mark_ignored=True)
    expect("ignored_records +1",
           detector.stats.ignored_records, 1)

    snapshot = detector.stats.as_dict()
    expect("snapshot new", snapshot["new_records"], 2)
    expect("snapshot duplicate", snapshot["duplicate_records"], 1)
    expect("snapshot updated", snapshot["updated_records"], 1)
    expect("snapshot ignored", snapshot["ignored_records"], 1)


# ---------------------------------------------------------------------------
# Section 5 — Scholarship model delegation
# ---------------------------------------------------------------------------

def test_model_delegation() -> None:
    banner("Scholarship model delegation")

    scholarship = Scholarship.from_dict(baseline_record())
    expect_true("generate_hash() is 64 chars",
                len(scholarship.generate_hash()) == 64)
    expect("duplicate_key() uses official_id",
           scholarship.duplicate_key(),
           "official_id::ft-001")

    no_id = Scholarship.from_dict(
        baseline_record(official_id=None)
    )
    expect("duplicate_key() falls back to apply_url",
           no_id.duplicate_key(),
           "apply_url::https://apply.example.com/fulbright")

    bare = Scholarship.from_dict(
        baseline_record(official_id=None, apply_url=None)
    )
    expect("duplicate_key() returns None when both missing",
           bare.duplicate_key(), None)


# ---------------------------------------------------------------------------
# Section 6 — bulk load + reset
# ---------------------------------------------------------------------------

def test_bulk_and_reset() -> None:
    banner("Bulk load + reset")

    detector = DuplicateDetector()
    seed = [
        baseline_record(),
        baseline_record(title="Scholarship B",
                        official_id="b-2",
                        apply_url="https://apply.example.com/b"),
    ]
    detector.bulk_load(seed)
    expect("bulk_load size", len(detector), 2)

    # New record hits existing apply_url.
    dup = baseline_record(official_id="different",
                          apply_url="https://apply.example.com/b")
    expect_true("bulk-loaded apply_url recognised",
                detector.check(dup).is_duplicate)

    detector.reset()
    expect("reset size == 0", len(detector), 0)
    expect("reset stats zeroed",
           detector.stats.new_records
           + detector.stats.duplicate_records
           + detector.stats.updated_records
           + detector.stats.ignored_records, 0)


# ---------------------------------------------------------------------------
# Section 7 — performance gate (10k records)
# ---------------------------------------------------------------------------

def test_performance() -> None:
    banner("Performance (10k records)")

    detector = DuplicateDetector(fuzzy_candidate_limit=200)

    # Seed with 10k synthetic records. Use a sequential official_id
    # and unique titles so the index stays diverse.
    records = []
    for i in range(10_000):
        records.append(baseline_record(
            title=f"Scholarship Programme {i}",
            official_id=f"id-{i}",
            apply_url=f"https://apply.example.com/{i}",
            university=f"University {i}",
        ))

    start = time.perf_counter()
    detector.bulk_load(records)
    load_seconds = time.perf_counter() - start

    # 10k bulk load should complete in well under a second on a normal
    # machine. Allow generous headroom for CI.
    expect("bulk_load <2s for 10k", load_seconds < 2.0, True)

    # Primary lookup against a fresh incoming record.
    fresh = baseline_record(
        title="Scholarship Programme 5000",
        official_id="id-9999",
        apply_url="https://apply.example.com/5000",
        university="Different University",
    )
    start = time.perf_counter()
    result = detector.check(fresh)
    check_seconds = time.perf_counter() - start

    expect_true("primary lookup found duplicate", result.is_duplicate)
    expect("primary lookup <50ms", check_seconds < 0.05, True)

    # Truly new record.
    brand_new = baseline_record(
        title="Brand New Scholarship",
        official_id="bn-1",
        apply_url="https://apply.example.com/brand-new",
        university="Unknown",
    )
    expect_false("brand new not duplicate",
                 detector.check(brand_new).is_duplicate)


# ---------------------------------------------------------------------------
# Section 8 — convenience helpers
# ---------------------------------------------------------------------------

def test_convenience() -> None:
    banner("Convenience helpers")

    result = DuplicateResult(is_duplicate=True, matched_by="content_hash")
    expect_true("DuplicateResult truthy when duplicate", bool(result))
    expect("matched_by propagated", result.matched_by, "content_hash")

    stats = DuplicateStats()
    expect("fresh stats are zero", stats.as_dict(),
           {"new_records": 0,
            "duplicate_records": 0,
            "updated_records": 0,
            "ignored_records": 0})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    """Run every section and return the process exit code."""
    test_pure_helpers()
    test_primary_lookup()
    test_fuzzy_lookup()
    test_statistics()
    test_model_delegation()
    test_bulk_and_reset()
    test_performance()
    test_convenience()

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
    print("All duplicate-detection checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())