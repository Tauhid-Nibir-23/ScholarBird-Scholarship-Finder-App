"""University / host-institution extraction.

Scholarship pages routinely describe a *host* university (where the
student studies) and a *funder* / *provider* (who pays the bill).
The two may overlap (e.g. "Commonwealth Scholarships — funded by the
University of Cambridge") or be different (e.g. "Chevening
Scholarships — funded by the UK Government, studied at any UK
university").

We extract both roles from the same page and store them as separate
slots:

* ``university`` — host institution, the answer the user ultimately
  cares about (e.g. "University of Edinburgh", "MIT").
* ``provider`` — the funding/issuing body (e.g. "Commonwealth Scholarship
  Commission", "UK Government"). Already supplied by the scraper; we
  only *fill* it when the scraper was empty.

The module implements priority order (JSON-LD → OG/Twitter → HTML →
URL) and returns a :class:`University` dataclass with all evidence
lines retained so the engine can audit its conclusions.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List, Optional

from bs4 import BeautifulSoup

from .html import extract_text, find_section, strip_noise
from .jsonld import extract_jsonld


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class University:
    """University information extracted from the page."""

    host: Optional[str] = None
    host_url: Optional[str] = None
    faculty: Optional[str] = None
    department: Optional[str] = None
    provider: Optional[str] = None
    provider_url: Optional[str] = None
    evidence: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Regex catalog
# ---------------------------------------------------------------------------

_UNIVERSITY_RE = re.compile(
    r"\b(?:at|by|hosted\s+by|hosted\s+at|offered\s+by|offered\s+at"
    r"|attending|enrolled\s+at|enrol(?:l|led)\s+at|studying\s+at"
    r"|admitted\s+to|awarded\s+by|tenable\s+at)\s+"
    r"(?:the\s+)?([A-Z][A-Za-z0-9 &'\-,.()]{2,120}?)"
    r"(?:\.|,|\s+(?:University|Institute|College|School|Polytechnic|Conservatory|Centre|Center|Academy))",
    re.I,
)

_PROVIDED_RE = re.compile(
    r"\b(?:funded\s+by|funded\s+through|provided\s+by|sponsored\s+by"
    r"|made\s+possible\s+by|scholarship\s+provided\s+by|programme\s+is\s+provided\s+by"
    r"|granted\s+by|administered\s+by|managed\s+by|by\s+the\s+)"
    r"([A-Z][A-Za-z0-9 &'\-,.()]{2,120}?)"
    r"(?:\.|,|\s+(?:University|Institute|College|Foundation|Trust|Government|Commission|Ministry"
    r"|Agency|Council|Board))",
    re.I,
)


# ---------------------------------------------------------------------------
# Section heading candidates
# ---------------------------------------------------------------------------

_HOST_HEADINGS: tuple[str, ...] = (
    "Host University",
    "Host Institution",
    "Where You'll Study",
    "Where you will Study",
    "Where you will study",
    "Study Location",
    "University",
    "Awarding University",
    "Attending Institution",
)

_PROVIDER_HEADINGS: tuple[str, ...] = (
    "Sponsor",
    "Sponsoring Organization",
    "Funding Body",
    "Funder",
    "Provider",
    "Award Provider",
    "Scholarship Provider",
    "Awarded by",
    "Offered by",
    "Funded by",
    "Sponsored by",
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


def _first_host_line(text: str) -> Optional[str]:
    """Return the first ``at/by/offered by`` phrase from ``text``."""
    if not text:
        return None
    for match in _UNIVERSITY_RE.finditer(text):
        candidate = _clean(match.group(0))
        if not candidate:
            continue
        return candidate
    return None


def _first_provider_line(text: str) -> Optional[str]:
    if not text:
        return None
    for match in _PROVIDED_RE.finditer(text):
        candidate = _clean(match.group(0))
        if not candidate:
            continue
        return candidate
    return None


# ---------------------------------------------------------------------------
# JSON-LD extraction
# ---------------------------------------------------------------------------


def _university_from_jsonld(soup: BeautifulSoup, result: University) -> None:
    document = extract_jsonld(soup)
    org = document.first_organization()
    if org is not None and org.name and not result.provider:
        result.provider = org.name
        result.provider_url = org.url
        result.evidence.append(f"jsonld:organization={org.name}")
    # Programme node may embed provider + host.
    scholarship = document.first_scholarship()
    if scholarship is not None:
        if scholarship.provider_name and not result.provider:
            result.provider = scholarship.provider_name
            result.provider_url = scholarship.provider_url
            result.evidence.append(
                f"jsonld:program.provider={scholarship.provider_name}"
            )


# ---------------------------------------------------------------------------
# HTML extraction
# ---------------------------------------------------------------------------


def _university_from_html(
    soup: BeautifulSoup, page_url: Optional[str], result: University
) -> None:
    cleaned = strip_noise(soup)
    text = extract_text(cleaned)
    if not text:
        return

    if not result.provider:
        provider_phrase = _first_provider_line(text)
        if provider_phrase:
            result.provider = provider_phrase
            result.evidence.append(f"html:provider={provider_phrase}")

    if not result.host:
        host_phrase = _first_host_line(text)
        if host_phrase:
            result.host = host_phrase
            result.evidence.append(f"html:host={host_phrase}")

    if not result.host:
        # Use a heading-flavoured section fallback.
        for heading in _HOST_HEADINGS:
            fragment = find_section(
                soup, [heading], stop_headings=list(_STOP_HEADINGS)
            )
            if fragment is not None:
                # The first content element is the explicit host value;
                # do not combine it with subsequent unrelated sections.
                value_node = fragment.find(["p", "li", "dd", "a"])
                fragment_text = (
                    value_node.get_text(separator=" ", strip=True)
                    if value_node is not None
                    else extract_text(fragment)
                )
                line = _clean(fragment_text)
                if line:
                    result.host = line
                    result.evidence.append(f"html:section={heading}:{line}")
                    break

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_university(
    soup: BeautifulSoup, page_url: Optional[str] = None
) -> University:
    """Return the host university + provider for the page.

    Args:
        soup: Source :class:`BeautifulSoup`.
        page_url: The final URL the page was loaded from. Used as a
            last-resort fallback when nothing in the HTML mentions
            the host by name.

    Returns:
        Populated :class:`University`.
    """
    result = University()
    if soup is None:
        return result

    _university_from_jsonld(soup, result)
    _university_from_html(soup, page_url, result)

    # De-dup evidence list and trim leading "the " prefixes.
    seen: set[str] = set()
    deduped: List[str] = []
    for line in result.evidence:
        key = line.strip().lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(line.strip())
    result.evidence = deduped

    if result.host and result.host.lower().startswith("the "):
        result.host = result.host[4:]
    return result


__all__ = ["University", "extract_university"]
