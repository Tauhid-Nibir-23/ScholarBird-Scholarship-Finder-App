"""Deadline / key-date extraction.

Many pages announce the application deadline using a single sentence
or a table cell. We surface the textual statement and (when possible)
a normalised ISO 8601 date.

Order of operations:

1. Look inside a deadline-flavoured section (h2/h3/dd labeled
   "Application Deadline", "Deadline", "Last Date", etc.).
2. Look for explicit datetime / date attributes
   (``<time datetime="...">``).
3. Fall back to the cleaned page text and scan for natural-language
   date phrases.

The function never invents a date. When extraction fails, the
:class:`Deadline` returns ``raw=None`` and downstream code may treat
the field as empty.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional

from bs4 import BeautifulSoup, Tag

from .html import extract_text, find_section, strip_noise


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class Deadline:
    """A single deadline reference extracted from a page."""

    raw: Optional[str] = None
    iso: Optional[str] = None
    date: Optional[datetime] = None
    timezone: Optional[str] = None
    notes: List[str] = field(default_factory=list)

    @property
    def is_set(self) -> bool:
        return self.raw is not None or self.date is not None


# ---------------------------------------------------------------------------
# Heading candidates
# ---------------------------------------------------------------------------

_HEADINGS: tuple[str, ...] = (
    "Application Deadline",
    "Deadline",
    "Last Date to Apply",
    "Last Date",
    "Submission Deadline",
    "Apply By",
    "Closing Date",
    "Due Date",
    "Application Closing Date",
    "Application Dates",
    "Key Dates",
    "Important Dates",
)

_STOP_HEADINGS: tuple[str, ...] = (
    "Eligibility",
    "Application Procedure",
    "How to Apply",
    "Benefits",
    "Funding",
    "Coverage",
    "Contact",
    "Frequently Asked Questions",
    "FAQs",
    "FAQ",
)


# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

# Format patterns (in priority order; first match wins).
_DATE_PATTERNS: tuple[tuple[str, re.Pattern], ...] = (
    (
        "ISO",
        re.compile(
            r"\b(20\d{2})-(\d{2})-(\d{2})(?:[T\s](\d{2}:\d{2}"
            r"(?::\d{2})?)(?:Z|([+-]\d{2}:?\d{2}))?)?\b"
        ),
    ),
    (
        "Month Day, Year",
        re.compile(
            r"\b(?:January|February|March|April|May|June|July"
            r"|August|September|October|November|December)"
            r"\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(20\d{2})\b"
        ),
    ),
    (
        "Day Month Year",
        re.compile(
            r"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"
            r"(?:January|February|March|April|May|June|July"
            r"|August|September|October|November|December)"
            r"\s+,?\s*(20\d{2})\b"
        ),
    ),
    (
        "Month Day (no year)",
        re.compile(
            r"\b(?:January|February|March|April|May|June|July"
            r"|August|September|October|November|December)"
            r"\s+(\d{1,2})(?:st|nd|rd|th)?(?!\s*,?\s*\d{4})\b"
        ),
    ),
    (
        "Numeric MM/DD/YYYY",
        re.compile(r"\b(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])/(20\d{2})\b"),
    ),
    (
        "Numeric DD/MM/YYYY",
        re.compile(r"\b(0?[1-9]|[12]\d|3[01])/(0?[1-9]|1[0-2])/(20\d{2})\b"),
    ),
)


_RANGE_RE = re.compile(
    r"\b(?:from|by|until)\s+(.+?)(?:\.|;|\n|$)",
    re.I,
)

_DEADLINE_PREFIX_RE = re.compile(
    r"\b(?:deadline(?:\s+is)?|apply\s+by|last\s+date\s+(?:to\s+apply\s+)?"
    r"|submission\s+deadline(?:\s+is)?|closing\s+date(?:\s+is)?"
    r"|due\s+date(?:\s+is)?)\s*[:\-–]?\s*(.+)",
    re.I,
)

_TZ_RE = re.compile(r"\b(?:UTC|GMT|EST|EDT|PST|PDT|GMT[-+]\d{1,2})\b")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


_MONTH_NAMES: dict[str, int] = {
    "january": 1, "february": 2, "march": 3, "april": 4,
    "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12,
}


def _clean_text(snippet: str) -> str:
    return re.sub(r"\s+", " ", snippet or "").strip()


def _parse_iso(value: str) -> Optional[datetime]:
    """Try multiple ISO date formats."""
    if not value:
        return None
    candidates = [
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
    ]
    cleaned = value.rstrip("Z")
    if "+" in cleaned[10:] or (len(cleaned) >= 6 and cleaned[-6] == "-"):
        # Strip offset since Python strptime doesn't parse +HH:MM.
        cleaned = cleaned[: max(0, len(cleaned) - 6)]
    for fmt in candidates:
        try:
            return datetime.strptime(cleaned, fmt)
        except ValueError:
            continue
    return None


def _parse_named(
    match: re.Match, kind: str
) -> Optional[datetime]:
    """Parse a named ``Month Day, Year`` / numeric date match."""
    text = match.group(0)
    if kind == "ISO":
        date_str = match.group(0)[:10]
        try:
            return datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
            return None
    if kind == "Month Day, Year":
        # Re-scan to extract month name + day + year robustly.
        month_name = match.group(0).split(",")[0].split(" ")[0].lower()
        day = int(match.group(1))
        year = int(match.group(2))
    elif kind == "Day Month Year":
        day = int(match.group(1))
        rest = match.group(0).lower()
        month_name = re.search(
            r"(january|february|march|april|may|june|july|august"
            r"|september|october|november|december)",
            rest,
        )
        month_name = month_name.group(0) if month_name else None
        year = int(match.group(2))
    elif kind == "Numeric MM/DD/YYYY":
        month = int(match.group(1))
        day = int(match.group(2))
        year = int(match.group(3))
        try:
            return datetime(year, month, day)
        except ValueError:
            return None
    elif kind == "Numeric DD/MM/YYYY":
        day = int(match.group(1))
        month = int(match.group(2))
        year = int(match.group(3))
        try:
            return datetime(year, month, day)
        except ValueError:
            return None
    else:
        return None

    if not month_name:
        return None
    month = _MONTH_NAMES.get(month_name)
    if month is None:
        return None
    try:
        return datetime(year, month, day)
    except ValueError:
        return None


def _parse_date(text: str) -> tuple[Optional[datetime], Optional[str]]:
    """Return ``(date, full_match)`` for the strongest date phrase in ``text``."""
    if not text:
        return None, None

    # 1. <time datetime="..."> tags.
    # Caller doesn't have the tree here, so we rely on the text path.

    # 2. Strong patterns first.
    for kind, pattern in _DATE_PATTERNS:
        for match in pattern.finditer(text):
            date = _parse_named(match, kind)
            if date is not None:
                return date, match.group(0).strip()
    return None, None


def _first_deadline_sentence(text: str) -> Optional[str]:
    """Return the sentence that announces the deadline."""
    if not text:
        return None
    for match in _DEADLINE_PREFIX_RE.finditer(text):
        snippet = _clean_text(match.group(1))
        if snippet:
            # Slice the snippet at the first sentence terminator.
            for terminator in (".", ";", "\n"):
                if terminator in snippet:
                    snippet = snippet.split(terminator, 1)[0].strip()
                    break
            return snippet
    return None


def _timezone_from_text(text: str) -> Optional[str]:
    match = _TZ_RE.search(text)
    return match.group(0) if match else None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_deadline(soup: BeautifulSoup) -> Deadline:
    """Return the deadline announcement from the page.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Populated :class:`Deadline`.
    """
    result = Deadline()
    if soup is None:
        return result

    cleaned = strip_noise(soup)
    if not cleaned or not cleaned.get_text(strip=True):
        return result

    # 1. <time datetime="..."> tags anywhere on the page.
    for time_tag in cleaned.find_all("time"):
        if not isinstance(time_tag, Tag):
            continue
        dt_attr = time_tag.get("datetime")
        if not dt_attr:
            continue
        text = time_tag.get_text(separator=" ", strip=True)
        date = _parse_iso(str(dt_attr))
        if date is not None:
            result.date = date
            result.iso = str(dt_attr).strip()
            result.raw = text or str(dt_attr).strip()
            tz = _timezone_from_text(text)
            if tz is None:
                tz = _timezone_from_text(str(dt_attr))
            result.timezone = tz
            if date.tzinfo is None:
                date = date.replace(tzinfo=timezone.utc)
            return result

    # 2. Use a deadline-flavoured section.
    fragment = find_section(
        cleaned,
        list(_HEADINGS),
        stop_headings=list(_STOP_HEADINGS),
    )
    if fragment is not None:
        text = extract_text(fragment)
        deadline_sentence = _first_deadline_sentence(text)
        if deadline_sentence:
            result.raw = deadline_sentence
            date, phrase = _parse_date(deadline_sentence)
            if date is not None:
                result.date = date
                result.iso = date.strftime("%Y-%m-%d")
                result.timezone = _timezone_from_text(deadline_sentence)
                if not result.timezone:
                    result.timezone = "UTC"
                return result

    # 3. Whole-page search for any deadline-prefix sentence.
    page_text = extract_text(cleaned)
    if page_text:
        deadline_sentence = _first_deadline_sentence(page_text)
        if deadline_sentence:
            result.raw = deadline_sentence
            date, phrase = _parse_date(deadline_sentence)
            if date is not None:
                result.date = date
                result.iso = date.strftime("%Y-%m-%d")
                result.timezone = _timezone_from_text(deadline_sentence)
                if not result.timezone:
                    result.timezone = "UTC"
                return result
            # Even if we have no date, surface the raw sentence + extracted
            # pieces (e.g. "Apply by January 31, 2026 — rolling admissions").
            result.notes.append(deadline_sentence)

    return result


__all__ = ["Deadline", "extract_deadline"]
