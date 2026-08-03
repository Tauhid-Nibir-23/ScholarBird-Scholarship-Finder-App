"""Degree-level extraction.

Pages state the eligible programmes in plain English ("Bachelor's,
Master's"), in lists ("Undergraduate, Graduate"), or in structured
data (``<degreeLevel>`` in metadata, ``educationalCredentialAwarded``
in JSON-LD).

The module is canonical for the ScholarBird domain. The mapping is
intentionally explicit so review and extension are easy:

===========  ===========================  ============================
Alias        :class:`DegreeLevel` value   Flutter label
===========  ===========================  ============================
bachelors    ``BACHELORS``                Bachelor's
masters      ``MASTERS``                  Master's
phd          ``PHD``                       PhD
diploma      ``DIPLOMA``                   Diploma
postdoc      ``POSTDOC``                   Post Doctorate
certificate  ``CERTIFICATE``               Certificate
high_school  ``HIGH_SCHOOL``               High School
foundation   ``FOUNDATION``                Foundation
short_course ``SHORT_COURSE``              Short Course
mba          ``MBA``                       MBA
law          ``LAW``                       Law
medical      ``MEDICAL``                   Medical
===========  ===========================  ============================

Multi-degree pages return every level that was explicitly stated —
never a default. The :class:`Degree` dataclass keeps raw evidence
lines so the engine can audit.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Sequence

from bs4 import BeautifulSoup

from .html import extract_text, find_section, strip_noise


# ---------------------------------------------------------------------------
# Degree levels
# ---------------------------------------------------------------------------


class DegreeLevel(str, Enum):
    """Supported scholarship degree levels."""

    BACHELORS = "Bachelors"
    MASTERS = "Masters"
    PHD = "PhD"
    DIPLOMA = "Diploma"
    POSTDOC = "Post Doctorate"
    CERTIFICATE = "Certificate"
    HIGH_SCHOOL = "High School"
    FOUNDATION = "Foundation"
    SHORT_COURSE = "Short Course"
    MBA = "MBA"
    LAW = "Law"
    MEDICAL = "Medical"
    UNKNOWN = "Unknown"


# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

_DEGREE_PATTERNS: tuple[tuple[DegreeLevel, Sequence[str], re.Pattern], ...] = (
    (
        DegreeLevel.BACHELORS,
        (
            r"\bbachelor(?:'s|s|\s+degree)?s?\b",
            r"\bundergraduate\b",
            r"\bbsc\b",
            r"\bb\.?a\.?\b",
            r"\bbba\b",
            r"\b(?:first|1st)\s+degree\b",
        ),
        re.compile(
            r"\bbachelor(?:'s|s|\s+degree)?s?\b|\bundergraduate\b"
            r"|\bbsc\b|\bbba\b|\bfirst\s+degree\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.MASTERS,
        (
            r"\bmaster(?:'s|s|\s+degree)?s?\b",
            r"\bmsc\b",
            r"\bm\.?s\.?\b",
            r"\b(?:post)?graduate\b",
            r"\bma\b",
        ),
        re.compile(
            r"\bmaster(?:'s|s|\s+degree)?s?\b|\bmsc\b|\bm\.?s\.?\b"
            r"|\bma\b|\bpostgraduate\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.PHD,
        (
            r"\bph\.?d\.?\b",
            r"\bdoctor(?:al|ate)\b",
            r"\bdoctoral\b",
            r"\bdphil\b",
            r"\bresearch\s+degree\b",
        ),
        re.compile(
            r"\bph\.?d\.?\b|\bdoctor(?:al|ate)\b|\bdphil\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.DIPLOMA,
        (r"\bdiploma\b", r"\b(?:post[- ]?graduate|graduate)\s+diploma\b"),
        re.compile(r"\bdiploma\b", re.I),
    ),
    (
        DegreeLevel.POSTDOC,
        (r"\bpost[-\s]?doc(?:toral)?\b", r"\bpost[\s-]doctoral\b"),
        re.compile(r"\bpost[-\s]?doc(?:toral)?\b", re.I),
    ),
    (
        DegreeLevel.CERTIFICATE,
        (r"\bcertificate\b", r"\bcert(?:ification)?\b"),
        re.compile(r"\bcertificate\b|\bcert(?:ification)?\b", re.I),
    ),
    (
        DegreeLevel.HIGH_SCHOOL,
        (
            r"\bhigh\s+school\b",
            r"\bsecondary\s+school\b",
            r"\b(?:a[-\s]?levels?|a[-\s]?level)\b",
        ),
        re.compile(
            r"\bhigh\s+school\b|\bsecondary\s+school\b|\ba[-\s]?levels?\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.FOUNDATION,
        (
            r"\bfoundation\s+(?:program|programme|year)\b",
            r"\bprep(?:aratory)?\s+(?:year|program|programme)\b",
        ),
        re.compile(
            r"\bfoundation\s+(?:program|programme|year)\b"
            r"|\bprep(?:aratory)?\s+(?:year|program|programme)\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.SHORT_COURSE,
        (r"\bshort\s+course\b", r"\bsummer\s+course\b", r"\bsummer\s+school\b"),
        re.compile(
            r"\bshort\s+course\b|\bsummer\s+course\b|\bsummer\s+school\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.MBA,
        (r"\bmba\b", r"\bm\.?b\.?a\.?\b", r"\bmaster\s+of\s+business"),
        re.compile(
            r"\bmba\b|\bm\.?b\.?a\.?\b|\bmaster\s+of\s+business",
            re.I,
        ),
    ),
    (
        DegreeLevel.LAW,
        (r"\b(?:ll\.?b\.?|ll\.?m\.?|jd|j\.d\.?|law\s+degree)\b",),
        re.compile(
            r"\bll\.?b\.?\b|\bll\.?m\.?\b|\bjd\b|\bj\.d\.?\b"
            r"|\blaw\s+degree\b",
            re.I,
        ),
    ),
    (
        DegreeLevel.MEDICAL,
        (
            r"\b(?:mbbs|md|m\.?d\.?|medical\s+degree|medicine\s+degree)\b",
        ),
        re.compile(
            r"\bmbbs\b|\bmd\b|\bm\.?d\.?\b"
            r"|\bmedical\s+degree\b|\bmedicine\s+degree\b",
            re.I,
        ),
    ),
)


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class Degree:
    """Degree information extracted from the page."""

    primary: Optional[DegreeLevel] = None
    levels: List[DegreeLevel] = field(default_factory=list)
    evidence: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Section heading candidates
# ---------------------------------------------------------------------------

_HEADINGS: tuple[str, ...] = (
    "Eligible Programme",
    "Eligible Programs",
    "Eligible Programmes",
    "Programmes",
    "Programs",
    "Study Level",
    "Study Levels",
    "Level of Study",
    "Qualification",
    "Qualifications",
    "Degree Level",
    "Degree Levels",
    "Who Can Apply",
    "Eligible Applicants",
)

_STOP_HEADINGS: tuple[str, ...] = (
    "Eligibility",
    "Application Procedure",
    "How to Apply",
    "Benefits",
    "Funding",
    "Deadline",
    "Contact",
    "Frequently Asked Questions",
    "FAQs",
    "FAQ",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _clean(snippet: str) -> str:
    return re.sub(r"\s+", " ", snippet or "").strip()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_degree(soup: BeautifulSoup) -> Degree:
    """Return the eligible degree levels found on ``soup``.

    The function never defaults to "Unknown" — when nothing matches,
    ``primary`` and ``levels`` remain ``None`` / ``[]`` so downstream
    code treats the field as empty.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Populated :class:`Degree`.
    """
    result = Degree()
    if soup is None:
        return result

    cleaned = strip_noise(soup)
    page_text = extract_text(cleaned)
    if not page_text:
        return result

    # 1. Walk a degree-flavoured section when present.
    section_text = ""
    for heading in _HEADINGS:
        fragment = find_section(
            soup,
            [heading],
            stop_headings=list(_STOP_HEADINGS),
        )
        if fragment is not None:
            candidate = extract_text(fragment)
            if candidate:
                section_text = candidate
                break
    haystack = section_text or page_text

    # 2. Run every alias regex against the haystack.
    found: list[DegreeLevel] = []
    evidence: list[str] = []
    for level, aliases, _pattern in _DEGREE_PATTERNS:
        for alias in aliases:
            pattern = re.compile(rf"(?:^|\W)({alias.strip()})(?:\W|$)", re.I)
            for match in pattern.finditer(haystack):
                snippet = _clean(match.group(0))
                if not snippet:
                    continue
                if level not in found:
                    found.append(level)
                    evidence.append(f"{level.value} :: {snippet}")
                break  # first match per alias is enough

    if found:
        result.levels = found
        result.primary = found[0]
        result.evidence = evidence
    return result


__all__ = ["Degree", "DegreeLevel", "extract_degree"]
