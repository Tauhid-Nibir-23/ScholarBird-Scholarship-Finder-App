"""Description cleanup for storage.

Raw scraped descriptions contain:

* navigation crumbs and breadcrumb lines,
* cookie banners ("This site uses cookies..."),
* footer blocks ("© 2026 University of X", "Privacy Policy"),
* share / social buttons ("Tweet this", "Share on Facebook"),
* styling artefacts ("×", "→", "•") and excessive whitespace,
* duplicated paragraphs (the same sentence repeated twice).

This module reduces any HTML page to a clean, single-paragraph
description that is safe to persist to Firestore and to ship to the
Flutter client.

The module exports :func:`clean_description` (the public entry
point) and :class:`Description` (the return shape, with optional
sections preserved as evidence lines).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List, Optional

from bs4 import BeautifulSoup, Tag

from .html import (
    deduplicate_lines,
    extract_text,
    strip_noise,
)


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class Description:
    """Cleaned description text + optional sectioned fallback."""

    primary: Optional[str] = None
    summary: Optional[str] = None
    evidence: List[str] = field(default_factory=list)
    dropped_blocks: int = 0

    def is_empty(self) -> bool:
        return not self.primary


# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

_COOKIE_RE = re.compile(
    r"\b(?:cookie[s]?|cookies?\s+(?:are|policy|consent|notification)"
    r"|accept\s+cookies|privacy\s+policy|terms\s+of\s+use|terms\s+&\s+conditions)\b",
    re.I,
)

_FOOTER_RE = re.compile(
    r"\b(?:copyright\s+©|©\s+\d{4}|all\s+rights\s+reserved"
    r"|(?:subscribe|sign\s+up)\s+(?:to|for)\s+our\s+newsletter"
    r"|(?:follow\s+us\s+on|visit\s+us\s+on|follow\s+on)\s+"
    r"(?:twitter|facebook|instagram|youtube|tiktok|linkedin|x\.com))",
    re.I,
)

_SHARE_RE = re.compile(
    r"\b(?:share\s+(?:this|on|via|now)|tweet\s+this|tweet\s+this\s+post"
    r"|like\s+us\s+on|pin\s+it\s+on|pinterest|whatsapp|telegram|reddit"
    r"|share\s+to\s+(?:facebook|twitter|linkedin))",
    re.I,
)

_NAV_RE = re.compile(
    r"\b(?:home\s*>\s*|skip\s+to\s+(?:main|content)|back\s+to\s+top|page\s+navigation)\b",
    re.I,
)

_TAGLINE_RE = re.compile(
    r"\b(?:apply\s+now|register\s+now|click\s+here\s+to\s+apply"
    r"|learn\s+more|read\s+more|find\s+out\s+more|see\s+full\s+details)\b",
    re.I,
)

#: Whitespace runs reduced to a single space.
_WS_RE = re.compile(r"\s+")

#: ``-`` / bullet characters alone on a line.
_BULLET_LINE_RE = re.compile(r"^[\s\-\u2022\•\→\·\▪\▫]+$")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _split_sentences(text: str) -> List[str]:
    """Return sentences split on ``.``, ``!``, ``?`` — kept simple."""
    out: List[str] = []
    buf: List[str] = []
    for ch in text:
        buf.append(ch)
        if ch in ".!?":
            sentence = "".join(buf).strip()
            if sentence:
                out.append(sentence)
            buf = []
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def _is_noise_paragraph(text: str) -> bool:
    """Return ``True`` when ``text`` is cookie/footer/share/nav chatter."""
    if not text:
        return True
    low = text.strip()
    if not low:
        return True
    for pattern in (
        _COOKIE_RE,
        _FOOTER_RE,
        _SHARE_RE,
        _NAV_RE,
        _TAGLINE_RE,
    ):
        if pattern.search(low):
            return True
    return False


def _summary(text: str, max_chars: int = 280) -> Optional[str]:
    """Build a short summary from the first paragraph(s) of ``text``."""
    if not text:
        return None
    for paragraph in text.split("\n"):
        cleaned = _WS_RE.sub(" ", paragraph).strip()
        if not cleaned or _is_noise_paragraph(cleaned):
            continue
        if len(cleaned) > max_chars:
            cleaned = cleaned[: max_chars - 1].rstrip() + "…"
        return cleaned
    return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _extract_paragraphs(soup: BeautifulSoup) -> List[str]:
    """Return useful, ordered, deduplicated paragraphs from a soup."""
    if soup is None:
        return []
    tree = strip_noise(soup)
    paragraphs: List[str] = []
    selectors = ("p", "li", "blockquote", "article p", "section p")
    for selector in selectors:
        for tag in tree.select(selector):
            if not isinstance(tag, Tag):
                continue
            text = tag.get_text(separator=" ", strip=True)
            text = _WS_RE.sub(" ", text).strip()
            if not text:
                continue
            if _is_noise_paragraph(text):
                continue
            if text in paragraphs:
                continue
            paragraphs.append(text)
    if not paragraphs:
        # Final fallback — flatten every text node.
        text = extract_text(tree)
        for chunk in re.split(r"\n+", text):
            cleaned = _WS_RE.sub(" ", chunk).strip()
            if cleaned and not _is_noise_paragraph(cleaned):
                if cleaned not in paragraphs:
                    paragraphs.append(cleaned)
    return paragraphs


def clean_description(soup: BeautifulSoup) -> Description:
    """Return a clean description derived from ``soup``.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Populated :class:`Description`. ``primary`` is ``None`` when
        nothing usable was found.
    """
    result = Description()
    if soup is None:
        return result

    paragraphs = _extract_paragraphs(soup)
    if not paragraphs:
        return result

    # Drop paragraphs that look like nav/cookie/footer/share noise.
    useful: List[str] = []
    for paragraph in paragraphs:
        if _is_noise_paragraph(paragraph):
            result.dropped_blocks += 1
            continue
        useful.append(paragraph)

    if not useful:
        return result

    # Build the primary description from the first three useful
    # paragraphs joined with a space.
    primary_pieces = useful[:3]
    primary = " ".join(primary_pieces)
    primary = _WS_RE.sub(" ", primary).strip()
    primary = deduplicate_lines(primary)

    result.primary = primary or None
    result.summary = _summary(primary)
    result.evidence.extend(useful[:6])
    return result


__all__ = ["Description", "clean_description"]
