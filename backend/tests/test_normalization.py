"""Smoke tests for the normalisation + validation engine.

The harness exercises every public helper in
:mod:`backend.parser.normalize` and :mod:`backend.parser.validator`,
plus the :meth:`Scholarship.normalize` and :meth:`Scholarship.validate`
shortcuts on the dataclass.

Run from the repository root::

    python backend/tests/test_normalization.py

The script prints a PASS/FAIL summary at the end and exits with a
non-zero status code if any case failed.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow `python backend/tests/test_normalization.py` from any CWD.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.models.scholarship import Scholarship
from backend.parser import (
    DEGREE_BACHELORS,
    DEGREE_MASTERS,
    DEGREE_PHD,
    DEGREE_POSTDOC,
    FUNDING_FULLY_FUNDED,
    FUNDING_PARTIALLY_FUNDED,
    FUNDING_SELF_FUNDED,
    FUNDING_UNKNOWN,
    clean_text,
    normalize_country,
    normalize_deadline,
    normalize_degree,
    normalize_funding,
    normalize_scholarship,
    validate_scholarship,
)


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

_PASS: int = 0
_FAIL: int = 0
_FAILURES: list[str] = []


def check(label: str, actual: object, expected: object) -> None:
    """Assert ``actual == expected`` and update the global tally."""
    global _PASS, _FAIL
    if actual == expected:
        _PASS += 1
        print(f"  PASS  {label}")
    else:
        _FAIL += 1
        message = f"  FAIL  {label}  expected={expected!r}  actual={actual!r}"
        _FAILURES.append(message)
        print(message)


def banner(title: str) -> None:
    """Print a section header."""
    print()
    print(title)
    print("-" * len(title))


# ---------------------------------------------------------------------------
# Country
# ---------------------------------------------------------------------------

def test_country() -> None:
    banner("Country normalisation")
    cases = [
        ("Federal Republic of Germany", "Germany"),
        ("Deutschland", "Germany"),
        ("Germany", "Germany"),
        ("germany", "Germany"),
        ("United States of America", "USA"),
        ("USA", "USA"),
        ("United Kingdom of Great Britain", "United Kingdom"),
        ("UK", "United Kingdom"),
        ("The Netherlands", "Netherlands"),
        ("Holland", "Netherlands"),
        ("United Arab Emirates", "UAE"),
        ("UAE", "UAE"),
        ("  brazil  ", "Brazil"),
        ("", None),
        (None, None),
    ]
    for raw, expected in cases:
        check(f"country({raw!r})", normalize_country(raw), expected)


# ---------------------------------------------------------------------------
# Degree
# ---------------------------------------------------------------------------

def test_degree() -> None:
    banner("Degree normalisation")
    cases = [
        ("Master's", DEGREE_MASTERS),
        ("Masters", DEGREE_MASTERS),
        ("MSc", DEGREE_MASTERS),
        ("M.Sc", DEGREE_MASTERS),
        ("MS", DEGREE_MASTERS),
        ("Master of Science", DEGREE_MASTERS),
        ("MBA", DEGREE_MASTERS),
        ("Bachelor", DEGREE_BACHELORS),
        ("Bachelors", DEGREE_BACHELORS),
        ("BSc", DEGREE_BACHELORS),
        ("B.Sc", DEGREE_BACHELORS),
        ("Bachelor's", DEGREE_BACHELORS),
        ("Doctoral", DEGREE_PHD),
        ("PhD", DEGREE_PHD),
        ("Doctorate", DEGREE_PHD),
        ("Doctoral Candidate", DEGREE_PHD),
        ("Postdoctoral", DEGREE_POSTDOC),
        ("PostDoc", DEGREE_POSTDOC),
    ("post-doc", DEGREE_POSTDOC),
        ("Post-Doctoral Researcher", DEGREE_POSTDOC),
        ("", None),
        (None, None),
        ("Random string", None),
    ]
    for raw, expected in cases:
        check(f"degree({raw!r})", normalize_degree(raw), expected)


# ---------------------------------------------------------------------------
# Funding
# ---------------------------------------------------------------------------

def test_funding() -> None:
    banner("Funding normalisation")
    cases = [
        ("Fully funded", FUNDING_FULLY_FUNDED),
        ("Full funding", FUNDING_FULLY_FUNDED),
        ("100% funded", FUNDING_FULLY_FUNDED),
        ("Full scholarship", FUNDING_FULLY_FUNDED),
        ("Partial funding", FUNDING_PARTIALLY_FUNDED),
        ("Partially funded", FUNDING_PARTIALLY_FUNDED),
        ("Partial", FUNDING_PARTIALLY_FUNDED),
        ("Self funded", FUNDING_SELF_FUNDED),
        ("No funding", FUNDING_SELF_FUNDED),
        ("Unknown", FUNDING_UNKNOWN),
        ("", FUNDING_UNKNOWN),
        (None, FUNDING_UNKNOWN),
        ("Weird value", FUNDING_UNKNOWN),
    ]
    for raw, expected in cases:
        check(f"funding({raw!r})", normalize_funding(raw), expected)


# ---------------------------------------------------------------------------
# Deadline
# ---------------------------------------------------------------------------

def test_deadline() -> None:
    banner("Deadline normalisation")
    cases = [
        ("15 March 2026", "2026-03-15"),
        ("March 15, 2026", "2026-03-15"),
        ("2026-03-15", "2026-03-15"),
        ("31/12/2025", "2025-12-31"),
        ("12/31/2025", "2025-12-31"),
        ("15-Jun-2026", "2026-06-15"),
        ("See official page", None),
        ("Rolling", None),
        ("Open", None),
        ("TBA", None),
        ("Unknown", None),
        ("", None),
        (None, None),
        ("definitely not a date", None),
    ]
    for raw, expected in cases:
        check(f"deadline({raw!r})", normalize_deadline(raw), expected)


# ---------------------------------------------------------------------------
# Clean text
# ---------------------------------------------------------------------------

def test_clean_text() -> None:
    banner("Text cleaning")
    cases = [
        ("  hello   world  ", "hello world"),
        ("line1\nline2\nline3", "line1 line2 line3"),
        ("line1\r\nline2", "line1 line2"),
        ("hello!!!", "hello!"),
        ("wait...really??", "wait.really?"),
        ("hello---world", "hello-world"),
        ("Tom &amp; Jerry", "Tom Jerry"),
        ("Tab\there", "Tab here"),
        (None, ""),
        ("", ""),
    ]
    for raw, expected in cases:
        check(f"clean({raw!r})", clean_text(raw), expected)


# ---------------------------------------------------------------------------
# Validator
# ---------------------------------------------------------------------------

def _make_valid_record(**overrides: object) -> dict:
    base = {
        "title": "DAAD Scholarship",
        "country": "Germany",
        "degree": "Masters",
        "field": "Engineering",
        "deadline": "2026-03-15",
        "amount": "Fully Funded",
        "description": "A great programme.",
        "link": "https://example.com/apply",
        "apply_url": "https://example.com/apply-now",
        "source": "daad",
        "official_id": "daad-1",
        "university": "TU Munich",
        "eligibility": "All nationalities",
    }
    base.update(overrides)
    return base


def test_validator() -> None:
    banner("Validator")

    # Valid baseline
    valid = _make_valid_record()
    check("valid baseline", validate_scholarship(valid).is_valid, True)

    # Title empty
    bad = _make_valid_record(title="   ")
    check("empty title", validate_scholarship(bad).is_valid, False)
    check("empty title reason", "title" in validate_scholarship(bad).reason, True)

    # Country missing
    bad = _make_valid_record(country="")
    check("empty country", validate_scholarship(bad).is_valid, False)

    # Source missing
    bad = _make_valid_record(source="")
    check("empty source", validate_scholarship(bad).is_valid, False)

    # Bad URL
    bad = _make_valid_record(link="not a url")
    check("bad link", validate_scholarship(bad).is_valid, False)

    # Bad apply_url
    bad = _make_valid_record(apply_url="not a url")
    check("bad apply_url", validate_scholarship(bad).is_valid, False)

    # Optional fields can be missing
    minimal = {
        "title": "x",
        "country": "Germany",
        "source": "daad",
        "degree": "Masters",
        "field": "Eng",
        "deadline": None,
    }
    check("minimal valid", validate_scholarship(minimal).is_valid, True)

    # Deadline None is allowed
    valid_no_deadline = _make_valid_record(deadline=None)
    check("deadline None OK", validate_scholarship(valid_no_deadline).is_valid, True)


# ---------------------------------------------------------------------------
# Scholarship dataclass shortcuts
# ---------------------------------------------------------------------------

def test_scholarship_shortcuts() -> None:
    banner("Scholarship.normalize / validate shortcuts")
    raw = Scholarship(
        title="  German Academic Exchange  ",
        country="Deutschland",
        degree="MSc",
        field="Engineering",
        deadline="15 March 2026",
        amount="Fully funded",
        description="A great   programme!!!",
        link="https://example.com/apply",
        source="daad",
    )

    norm = raw.normalize()

    check("normalize().country", norm.country, "Germany")
    check("normalize().degree", norm.degree, DEGREE_MASTERS)
    check("normalize().deadline", norm.deadline, "2026-03-15")
    check("normalize().amount", norm.amount, FUNDING_FULLY_FUNDED)
    check("normalize().title cleaned", norm.title, "German Academic Exchange")
    check("normalize() preserves source", norm.source, "daad")

    check("normalize() valid", norm.validate(), True)

    # Original instance untouched (frozen dataclass)
    check("raw.country unchanged", raw.country, "Deutschland")
    check("raw.degree unchanged", raw.degree, "MSc")


# ---------------------------------------------------------------------------
# normalize_scholarship full pass
# ---------------------------------------------------------------------------

def test_normalize_record() -> None:
    banner("normalize_scholarship full pass")
    raw = {
        "title": "  Hello   World  ",
        "country": "Federal Republic of Germany",
        "degree": "Master's",
        "field": "Engineering",
        "deadline": "Rolling",
        "amount": "Fully funded",
        "description": "lorem  ipsum",
        "link": "https://example.com",
        "source": "daad",
        "tags": [" tag1 ", "tag2", "", "   "],
        "university": "TU Munich",
        "eligibility": "Open  to  all",
    }
    out = normalize_scholarship(raw)

    check("title cleaned", out["title"], "Hello World")
    check("country normalised", out["country"], "Germany")
    check("degree normalised", out["degree"], DEGREE_MASTERS)
    check("deadline Rolling -> None", out["deadline"], None)
    check("funding normalised", out["funding_type"], FUNDING_FULLY_FUNDED)
    check("amount == funding_type", out["amount"], FUNDING_FULLY_FUNDED)
    check("university cleaned", out["university"], "TU Munich")
    check("eligibility cleaned", out["eligibility"], "Open to all")
    check("tags cleaned", out["tags"], ["tag1", "tag2"])


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    test_country()
    test_degree()
    test_funding()
    test_deadline()
    test_clean_text()
    test_validator()
    test_scholarship_shortcuts()
    test_normalize_record()

    print()
    print("=" * 60)
    print(f"PASS: {_PASS}")
    print(f"FAIL: {_FAIL}")
    print("=" * 60)

    if _FAIL:
        print()
        print("Failures:")
        for failure in _FAILURES:
            print(failure)
        return 1
    print()
    print("All normalization + validation checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())