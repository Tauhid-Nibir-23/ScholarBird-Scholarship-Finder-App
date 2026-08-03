"""Eligibility / requirements extraction.

Pages embed admission rules in narrative prose, HTML lists, definition
lists, accordions, or tables — never in a canonical structure. This
module parses all of those.

The output is a :class:`Requirements` dataclass with the following
slots:

* ``languages`` — canonical list of language requirements, e.g.::

      [
          {
              "language": "English",
              "tests": ["IELTS", "TOEFL"],
              "minScores": [
                  {"test": "IELTS", "score": 6.5, "section": "Overall"},
              ],
              "mediumAccepted": False,
          }
      ]

* ``cgpa`` — minimum CGPA values found on the page::

      [{"scale": 4.0, "value": 3.0}, {"scale": 100.0, "value": 75.0}]

* ``research`` — research-only flag + extra context::

      {
          "required": True,
          "proposal": True,
          "supervisor": True,
          "publication": True,
          "evidence": ["research proposal required", ...],
      }

We never invent values. If a slot has no evidence in the page, it
defaults to a safe empty value (``False``, ``[]``, ``None``).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence

from bs4 import BeautifulSoup

from .html import (
    extract_text,
    find_definition_pairs,
    find_faq_pairs,
    find_section,
    strip_noise,
)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class MinScore:
    """A single min-score entry for a language test."""

    test: str
    score: float
    section: Optional[str] = None


@dataclass
class LanguageRequirement:
    """All language info extracted for a page (assumes English)."""

    language: str = "English"
    tests: List[str] = field(default_factory=list)
    min_scores: List[MinScore] = field(default_factory=list)
    medium_accepted: bool = False


@dataclass
class CGPAEntry:
    """A single CGPA reference."""

    scale: Optional[float] = None
    value: float = 0.0
    raw: Optional[str] = None


@dataclass
class ResearchRequirements:
    """Research-only programme flags + evidence."""

    required: bool = False
    proposal: bool = False
    supervisor: bool = False
    publication: bool = False
    evidence: List[str] = field(default_factory=list)


@dataclass
class Requirements:
    """All eligibility / requirements information from a page."""

    languages: List[LanguageRequirement] = field(default_factory=list)
    cgpa: List[CGPAEntry] = field(default_factory=list)
    research: ResearchRequirements = field(
        default_factory=ResearchRequirements
    )
    notes: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Test registry
# ---------------------------------------------------------------------------

# Each tuple: ``(test_name, regex, parser)``.
# ``parser`` accepts a regex match and returns the parsed score as a float.

_TEST_PATTERNS: List[tuple[str, re.Pattern, ...]] = [
    (
        "IELTS",
        re.compile(
            r"\bIELTS\b[^.\\n]{0,80}?"
            r"(?:overall|total|minimum)?[^.\\n]{0,40}?"
            r"(?P<score>\d+\.\d+|\d+)",
            re.I,
        ),
    ),
    (
        "TOEFL",
        re.compile(
            r"\b(?:TOEFL\s*i?BT|iBT\s*TOEFL|TOEFL[^.\\n]{0,40})[^.\\n]{0,60}?"
            r"(?:minimum|at\s*least|of)?[^.\\n]{0,30}?"
            r"(?P<score>\d{2,3})",
            re.I,
        ),
    ),
    (
        "PTE",
        re.compile(
            r"\bPTE(?:\s*Academic)?\b[^.\\n]{0,80}?"
            r"(?P<score>\d{2,3})",
            re.I,
        ),
    ),
    (
        "Duolingo",
        re.compile(
            r"\bDuolingo(?:\s*English\s*Test|\s*DET)?\b[^.\\n]{0,80}?"
            r"(?P<score>\d{2,3})",
            re.I,
        ),
    ),
    (
        "Cambridge",
        re.compile(
            r"\b(?:CAE|CPE|Cambridge\s*English(?:\s*Advanced)?)\b"
            r"[^.\\n]{0,80}?(?P<score>\d{3})",
            re.I,
        ),
    ),
]

_MOI_RE = re.compile(
    r"\b(?:medium\s+of\s+instruction|MOI)\b[^.\n]{0,80}",
    re.I,
)

_MOI_ACCEPT_RE = re.compile(
    r"\b(?:MOI|medium of instruction)"
    r"(?:[^.\n]{0,80})?(?:is\s+)?(?:acceptable|accepted|sufficient|satisfies)",
    re.I,
)

_ENGLISH_MEDIUM_RE = re.compile(
    r"\b(?:English\s+medium|English[\s-]language\s+of\s+instruction"
    r"|degree\s+taught\s+in\s+English|English-taught)\b"
    r"[^.\n]{0,80}\b(?:acceptable|accepted|sufficient|satisfies|waived)\b",
    re.I,
)


# ---------------------------------------------------------------------------
# CGPA patterns
# ---------------------------------------------------------------------------

_CGPA_PATTERNS: List[re.Pattern] = [
    re.compile(
        r"\b(?:minimum\s+(?:CGPA|GPA)|CGPA(?:\s+of)?|GPA(?:\s+of)?)\s*"
        r"(?:at\s+least)?\s*(?P<value>\d+\.\d+|\d+)"
        r"(?:\s*/\s*|\s+out\s+of\s+)(?P<scale>\d+\.\d+|\d+)?",
        re.I,
    ),
    re.compile(
        r"\b(?:minimum|at\s+least)\s+(?:of\s+|a\s+)?(?P<value>\d+\.\d+|\d+)\s*"
        r"(?:GPA|CGPA)",
        re.I,
    ),
]


# ---------------------------------------------------------------------------
# Research patterns
# ---------------------------------------------------------------------------

_RESEARCH_TERMS: Sequence[tuple[str, re.Pattern]] = (
    (
        "research required",
        re.compile(
            r"\b(?:research\s+(?:is\s+)?(?:required|essential|necessary"
            r"|must be conducted|experience))\b",
            re.I,
        ),
    ),
    (
        "research proposal",
        re.compile(
            r"\b(?:research\s+proposal|proposal\s+required)\b",
            re.I,
        ),
    ),
    (
        "supervisor",
        re.compile(
            r"\b(?:(?:find\s+a|secure\s+a|identify\s+a|with\s+a"
            r"|acceptance\s+letter\s+from\s+a|approved\s+supervisor"
            r"|(?<!no\s)supervisor\s+required)\s*supervisor)\b",
            re.I,
        ),
    ),
    (
        "publication",
        re.compile(
            r"\b(?:(?:peer[- ]reviewed\s+|refereed\s+)?publications?"
            r"|published\s+(?:a\s+|at\s+least\s+)?(?:paper|article)"
            r"|publication\s+(?:record|required))\b",
            re.I,
        ),
    ),
)


# ---------------------------------------------------------------------------
# Section heading candidates
# ---------------------------------------------------------------------------

_REQ_HEADINGS: tuple[str, ...] = (
    "Admission Requirements",
    "Admissions Requirements",
    "Eligibility",
    "Eligibility Criteria",
    "Who can apply",
    "Applicant Requirements",
    "Applicant Eligibility",
    "Entry Requirements",
    "Selection Criteria",
    "General Requirements",
    "English Language Requirements",
    "English Language Requirement",
    "Language Requirement",
    "Language Requirements",
    "Language Proficiency",
    "Academic Requirements",
    "Academic Qualification",
    "Required Documents",
    "Required Documentation",
    "Application Requirements",
)

_REQ_STOP_HEADINGS: tuple[str, ...] = (
    "Application Procedure",
    "How to Apply",
    "Benefits",
    "Funding",
    "Deadline",
    "Key dates",
    "Contact",
    "Frequently Asked Questions",
    "FAQs",
    "FAQ",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _sections_text(soup: BeautifulSoup) -> List[BeautifulSoup]:
    """Return ``find_section`` results for every ``_REQ_HEADINGS`` group."""
    fragments: List[BeautifulSoup] = []
    # Try each heading individually so the first match wins, then bail.
    for heading in _REQ_HEADINGS:
        fragment = find_section(
            soup,
            [heading],
            stop_headings=_REQ_STOP_HEADINGS,
        )
        if fragment is not None and fragment.get_text(strip=True):
            fragments.append(fragment)
    return fragments


def _first_float(match: re.Match, group: str) -> Optional[float]:
    try:
        value = match.group(group)
    except (IndexError, AttributeError):
        return None
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _safe_section(test: str, match: str) -> Optional[str]:
    """Return a section label for a regex match, if any."""
    text = match.lower()
    if "overall" in text:
        return "Overall"
    if "listening" in text:
        return "Listening"
    if "reading" in text:
        return "Reading"
    if "writing" in text:
        return "Writing"
    if "speaking" in text:
        return "Speaking"
    if "total" in text:
        return "Total"
    if "minimum" in text or "at least" in text:
        return "Minimum"
    return None


# ---------------------------------------------------------------------------
# Language + CGPA + research parsers
# ---------------------------------------------------------------------------


def _detect_english_exemptions(text: str) -> bool:
    """Return ``True`` when MOI / English-medium exemption is offered."""
    if not text:
        return False
    if _MOI_ACCEPT_RE.search(text):
        return True
    if _ENGLISH_MEDIUM_RE.search(text):
        return True
    return False


def _parse_languages(
    soup: BeautifulSoup, text: str
) -> List[LanguageRequirement]:
    """Return language requirements extracted from the page text."""
    requirement = LanguageRequirement()
    for name, pattern in _TEST_PATTERNS:
        for match in pattern.finditer(text):
            score = _first_float(match, "score")
            if score is None:
                continue
            if name not in requirement.tests:
                requirement.tests.append(name)
            requirement.min_scores.append(
                MinScore(
                    test=name,
                    score=score,
                    section=_safe_section(name, match.group(0)),
                )
            )

    requirement.medium_accepted = _detect_english_exemptions(text)
    # Always return English when evidence points to it OR when MOI/EM is
    # flagged (those are English-programme signals).
    if (
        requirement.tests
        or requirement.medium_accepted
        or re.search(r"\bEnglish\b", text)
    ):
        requirement.language = "English"
        return [requirement]
    return []


def _parse_cgpa(text: str) -> List[CGPAEntry]:
    """Return CGPA entries extracted from the page text."""
    entries: List[CGPAEntry] = []
    seen: set[tuple[Optional[float], float]] = set()
    for pattern in _CGPA_PATTERNS:
        for match in pattern.finditer(text):
            value = _first_float(match, "value")
            if value is None:
                continue
            scale = _first_float(match, "scale")
            key = (scale, value)
            if key in seen:
                continue
            seen.add(key)
            entries.append(
                CGPAEntry(scale=scale, value=value, raw=match.group(0).strip())
            )
    return entries


def _parse_research(soup: BeautifulSoup, text: str) -> ResearchRequirements:
    """Return research-only programme signals from the page."""
    research = ResearchRequirements()
    sections = _sections_text(soup)
    if not sections:
        # Fall back to the full page text — research-only flags are
        # sometimes summarised in the hero.
        haystack = text
    else:
        haystack = "\n".join(extract_text(s) for s in sections)

    section_lower = haystack.lower()
    for label, pattern in _RESEARCH_TERMS:
        for match in pattern.finditer(haystack):
            snippet = _clean_snippet(match.group(0))
            if not snippet:
                continue
            if label not in research.evidence:
                research.evidence.append(snippet)
    # Set booleans.
    research.required = any(
        "research" in ev and "required" in ev
        or "research is essential" in ev
        or "research must" in ev
        for ev in research.evidence
    )
    research.proposal = any(
        "research proposal" in ev.lower() or "proposal required" in ev.lower()
        for ev in research.evidence
    )
    research.supervisor = any(
        "supervisor" in ev.lower() for ev in research.evidence
    )
    research.publication = any(
        "publication" in ev.lower() or "published" in ev.lower()
        for ev in research.evidence
    )
    return research


def _clean_snippet(snippet: str) -> str:
    text = re.sub(r"\s+", " ", snippet or "")
    return text.strip()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


HEADING_CANDIDATES: tuple[str, ...] = _REQ_HEADINGS
STOP_HEADING_CANDIDATES: tuple[str, ...] = _REQ_STOP_HEADINGS


def extract_requirements(soup: BeautifulSoup) -> Requirements:
    """Run every requirements extractor over ``soup``.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        A populated :class:`Requirements` instance.
    """
    result = Requirements()
    if soup is None:
        return result

    cleaned = strip_noise(soup)
    page_text = extract_text(cleaned)
    if not page_text:
        return result

    sections = _sections_text(cleaned)
    section_text = "\n".join(extract_text(s) for s in sections)
    if not section_text.strip():
        section_text = page_text

    result.languages = _parse_languages(cleaned, section_text)
    result.cgpa = _parse_cgpa(section_text)
    result.research = _parse_research(cleaned, section_text)
    result.notes = _extract_notes(cleaned, section_text)

    return result


def _extract_notes(
    soup: BeautifulSoup, text: str
) -> List[str]:
    """Extract generic-but-useful requirement notes from the page."""
    notes: List[str] = []
    patterns = (
        r"\b(?:must\s+be\s+(?:a\s+)?citizen[^.\n]{0,80})",
        r"\b(?:work\s+permit\s+required[^.\n]{0,80})",
        r"\b(?:female[- ]only|women[- ]only)\b",
        r"\b(?:first[- ]degree\s+required[^.\n]{0,80})",
        r"\b(?:master['’]s\s+degree\s+required[^.\n]{0,80})",
        r"\b(?:bachelor['’]s\s+degree\s+required[^.\n]{0,80})",
        r"\b(?:at\s+least\s+one\s+year[^.\n]{0,80})",
        r"\b(?:two\s+years?\s+of\s+experience[^.\n]{0,80})",
    )
    for pattern in patterns:
        compiled = re.compile(pattern, re.I)
        for match in compiled.finditer(text):
            snippet = _clean_snippet(match.group(0))
            if snippet and snippet not in notes:
                notes.append(snippet)
    # Definition-list pairs make excellent requirements text.
    for term, definition in find_definition_pairs(soup):
        term_clean = term.strip()
        if not term_clean:
            continue
        candidate = f"{term_clean}: {definition.strip()}"
        if candidate not in notes and len(candidate) <= 240:
            notes.append(candidate)
    # FAQ pairs are also strong eligibility signal.
    for q, a in find_faq_pairs(soup):
        if not q:
            continue
        low_q = q.lower()
        if any(
            keyword in low_q
            for keyword in (
                "eligib",
                "require",
                "qualifi",
                "language",
                "ielts",
                "toefl",
                "cgpa",
                "gpa",
                "english",
            )
        ):
            candidate = f"{q.strip()}: {a.strip()}"[:240]
            if candidate not in notes:
                notes.append(candidate)
    return notes


__all__ = [
    "CGPAEntry",
    "LanguageRequirement",
    "MinScore",
    "Requirements",
    "ResearchRequirements",
    "extract_requirements",
]
