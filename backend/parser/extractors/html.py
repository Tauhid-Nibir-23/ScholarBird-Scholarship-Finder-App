"""HTML parsing primitives for the production extraction engine.

The module wraps BeautifulSoup with deterministic, dependency-light
helpers that the rest of the extractor package relies on:

* :func:`parse_html` — safe HTML parser factory (html.parser backend;
  no external ``lxml`` dependency).
* :func:`extract_text` — strip-and-collapse helper that turns a soup
  tree into a single searchable string.
* :func:`find_section` — locate a heading-anchored content block (used
  for "Admission Requirements", "Eligibility", "Funding", etc.).
* :func:`find_faq_pairs` — extract FAQ question/answer pairs.
* :func:`find_definition_pairs` — pull ``<dt>``/``<dd>`` pairs.
* :func:`extract_meta` — generic meta-tag reader that handles both
  ``property="..."`` and ``name="..."`` forms.
* :func:`strip_noise` — remove navigation/cookie/footer/script blocks
  before any text extraction.

Design notes
------------
* No AI inference, no defaults, no fabrication. Every helper returns
  what is literally present in the HTML.
* All helpers are tolerant of malformed HTML — they never raise on
  broken nesting or unterminated tags. They simply return less.
"""

from __future__ import annotations

import re
from typing import Iterable, List, Optional, Sequence, Tuple

from bs4 import BeautifulSoup, Tag


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

#: Tags we always strip before text extraction. ``<script>``/``<style>``
#: are noise; ``<noscript>`` is rarely useful for extraction.
_NOISE_TAGS: Tuple[str, ...] = ("script", "style", "noscript", "iframe")

#: Class / id patterns that identify chrome (navigation, footer, etc.).
#: Matched case-insensitively against ``class`` and ``id`` attributes.
_CHROME_PATTERNS: Tuple[str, ...] = (
    r"\bnav(?:igation|bar|menu)?\b",
    r"\bmenu\b",
    r"\bheader\b",
    r"\bfooter\b",
    r"\bbreadcrumb\b",
    r"\bsidebar\b",
    r"\bcookie\b",
    r"\bbanner\b",
    r"\badvert(?:isement)?\b",
    r"\bshare\b",
    r"\bsharing\b",
    r"\bshare-buttons?\b",
    r"\bsharebuttons?\b",
    r"\bsocial\b",
    r"\bpopup\b",
    r"\bmodal\b",
    r"\btooltip\b",
    r"\brelated\b",
    r"\bskip\b",
    r"\bhidden\b",
    r"\bcomments?\b",
    r"\bpagination\b",
    r"\bsearch-form\b",
    r"\bsubscribe\b",
    r"\bnewsletter\b",
    r"\bwidget\b",
    r"\bbottom-bar\b",
    r"\btop-bar\b",
)

_CHROME_RE = re.compile("|".join(_CHROME_PATTERNS), re.IGNORECASE)

#: Compile-time regex used by :func:`extract_text` to collapse
#: whitespace runs into a single space.
_WS_RE = re.compile(r"\s+")


# ---------------------------------------------------------------------------
# Parser factory
# ---------------------------------------------------------------------------


def parse_html(html: str) -> BeautifulSoup:
    """Return a :class:`BeautifulSoup` tree built with the stdlib parser.

    We deliberately use ``html.parser`` rather than ``lxml`` so the
    package has zero compiled-extension dependencies. BeautifulSoup's
    ``html.parser`` is robust on real-world pages.

    Args:
        html: Raw HTML body. ``None`` or empty values are tolerated
            and produce an empty soup.

    Returns:
        A parsed :class:`BeautifulSoup` instance.
    """
    if not html:
        return BeautifulSoup("", "html.parser")
    return BeautifulSoup(html, "html.parser")


# ---------------------------------------------------------------------------
# Text extraction
# ---------------------------------------------------------------------------


def strip_noise(soup: BeautifulSoup) -> BeautifulSoup:
    """Return a copy of ``soup`` with chrome blocks removed.

    The function removes elements matching any of the noise tags or
    whose ``class`` / ``id`` attribute matches a chrome pattern. It
    operates on a fresh copy so the caller's soup tree stays untouched.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        A new :class:`BeautifulSoup` with chrome blocks detached.
    """
    if soup is None:
        return BeautifulSoup("", "html.parser")
    # ``copy`` keeps the parser backend identical to the source.
    tree = BeautifulSoup(str(soup), "html.parser")

    # 1. Drop <script>, <style>, <noscript>, <iframe> entirely.
    for tag in tree.find_all(_NOISE_TAGS):
        tag.decompose()

    # 2. Drop elements whose class/id screams "navigation/footer/etc."
    for element in list(tree.find_all(True)):
        if not isinstance(element, Tag):
            continue
        attrs = " ".join(
            filter(
                None,
                [
                    " ".join(element.get("class") or []),
                    str(element.get("id") or ""),
                    str(element.get("role") or ""),
                ],
            )
        )
        if attrs and _CHROME_RE.search(attrs):
            element.decompose()

    return tree


def extract_text(
    soup: BeautifulSoup,
    *,
    strip: bool = True,
    collapse: bool = True,
) -> str:
    """Return the cleaned text content of ``soup``.

    The function calls :func:`strip_noise` internally, joins all
    surviving text nodes with a space, and collapses whitespace runs.

    Args:
        soup: Source :class:`BeautifulSoup` tree.
        strip: If ``True`` (default), strip leading/trailing whitespace.
        collapse: If ``True`` (default), collapse every whitespace run
            (including ``\\n``, ``\\t``) into a single space.

    Returns:
        Plain text body. Empty string when ``soup`` is ``None``.
    """
    if soup is None:
        return ""
    cleaned = strip_noise(soup)
    text = cleaned.get_text(separator=" ")
    if collapse:
        text = _WS_RE.sub(" ", text)
    if strip:
        text = text.strip()
    return text


# ---------------------------------------------------------------------------
# Section lookup
# ---------------------------------------------------------------------------

#: Heading-like tag names that may anchor a content section.
_HEADING_TAGS: Tuple[str, ...] = ("h1", "h2", "h3", "h4", "h5", "h6")


def find_section(
    soup: BeautifulSoup,
    headings: Sequence[str],
    *,
    stop_headings: Optional[Sequence[str]] = None,
) -> Optional[BeautifulSoup]:
    """Return the soup subtree that follows the first matching heading.

    Args:
        soup: Source :class:`BeautifulSoup`.
        headings: Section titles to match (case-insensitive). Matched
            against ``<h1>``…``<h6>`` text content. Multiple candidates
            are tried in order; the first hit wins.
        stop_headings: Optional list of headings that signal the end of
            the section (e.g. ``["Eligibility"]`` ends "Admission
            Requirements" once a sibling heading matches).

    Returns:
        A new :class:`BeautifulSoup` fragment containing every
        sibling element between the matched heading and the next
        stop heading (or the parent container's end). Returns
        ``None`` when no heading matches.
    """
    if soup is None or not headings:
        return None
    targets = {h.strip().lower() for h in headings if h and h.strip()}
    if not targets:
        return None
    stops = {
        h.strip().lower() for h in (stop_headings or []) if h and h.strip()
    }

    for heading in soup.find_all(_HEADING_TAGS):
        if not isinstance(heading, Tag):
            continue
        text = heading.get_text(separator=" ", strip=True).lower()
        if text in targets:
            return _slice_section(heading, stops)
    return None


def _slice_section(
    heading: Tag, stop_headings: Iterable[str]
) -> BeautifulSoup:
    """Collect siblings after ``heading`` up to the next stop heading."""
    fragment = BeautifulSoup("", "html.parser")
    container = heading.parent
    if container is None:
        # Heading is the root — return just the heading.
        return BeautifulSoup(str(heading), "html.parser")
    children = list(container.children)
    try:
        start_index = children.index(heading) + 1
    except ValueError:
        return BeautifulSoup(str(heading), "html.parser")
    for sibling in children[start_index:]:
        if isinstance(sibling, Tag):
            inner_text = sibling.get_text(separator=" ", strip=True).lower()
            if sibling.name in _HEADING_TAGS and inner_text in stop_headings:
                break
        # Clone the sibling into the fragment so the source tree
        # remains intact.
        fragment.append(sibling.__copy__())
    return fragment


# ---------------------------------------------------------------------------
# FAQ + definition-list extraction
# ---------------------------------------------------------------------------


def find_faq_pairs(soup: BeautifulSoup) -> List[Tuple[str, str]]:
    """Return ``(question, answer)`` pairs from common FAQ markup.

    Recognises four patterns:

    * ``<details><summary>...</summary>...</details>``
    * ``<button class="accordion">...</button><div class="panel">...</div>``
    * ``<h3>...</h3><div class="faq-body">...</div>``
    * ``<div class="faq-item">…<div class="q">…</div><div class="a">…</div></div>``

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Pairs in source order. Empty list when nothing matches.
    """
    if soup is None:
        return []

    pairs: List[Tuple[str, str]] = []

    # Pattern 1: <details><summary>...</summary>...</details>
    for details in soup.find_all("details"):
        summary = details.find("summary")
        if summary is None:
            continue
        q = summary.get_text(separator=" ", strip=True)
        # ``decompose`` the summary so the answer text omits it.
        answer_soup = BeautifulSoup(str(details), "html.parser")
        for inner_summary in answer_soup.find_all("summary"):
            inner_summary.decompose()
        a = answer_soup.get_text(separator=" ", strip=True)
        if q and a:
            pairs.append((q, a))

    # Pattern 2: accordion — heading followed by panel
    for heading in soup.find_all(
        ["button", "h2", "h3", "h4"]
    ):
        if heading.name == "button":
            classes = " ".join(heading.get("class") or [])
            if not re.search(r"accordion|faq|question", classes, re.I):
                continue
        else:
            classes = " ".join(heading.get("class") or [])
            if not re.search(r"faq|question|accordion", classes, re.I):
                continue
        q = heading.get_text(separator=" ", strip=True)
        # Find next sibling that looks like a panel.
        panel = heading.find_next_sibling(
            ["div", "section", "article"]
        )
        if panel is None:
            continue
        panel_classes = " ".join(panel.get("class") or [])
        if not re.search(
            r"panel|faq-body|answer|collapse|content",
            panel_classes, re.I,
        ):
            continue
        a = panel.get_text(separator=" ", strip=True)
        if q and a:
            pairs.append((q, a))

    # Pattern 3: <div class="faq-item"><div class="q">…</div><div class="a">…</div></div>
    for item in soup.find_all(
        attrs={"class": re.compile(r"\bfaq[-_]?item\b", re.I)}
    ):
        q_node = item.find(
            attrs={"class": re.compile(r"\b(q|question)\b", re.I)}
        )
        a_node = item.find(
            attrs={"class": re.compile(r"\b(a|answer)\b", re.I)}
        )
        if q_node is not None and a_node is not None:
            q = q_node.get_text(separator=" ", strip=True)
            a = a_node.get_text(separator=" ", strip=True)
            if q and a:
                pairs.append((q, a))

    return pairs


def find_definition_pairs(
    soup: BeautifulSoup,
) -> List[Tuple[str, str]]:
    """Return ``(term, definition)`` pairs from every ``<dl>``.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Pairs in source order.
    """
    if soup is None:
        return []
    pairs: List[Tuple[str, str]] = []
    for dl in soup.find_all("dl"):
        terms = dl.find_all("dt")
        definitions = dl.find_all("dd")
        for term, definition in zip(terms, definitions):
            q = term.get_text(separator=" ", strip=True)
            a = definition.get_text(separator=" ", strip=True)
            if q and a:
                pairs.append((q, a))
    return pairs


# ---------------------------------------------------------------------------
# Meta-tag helpers
# ---------------------------------------------------------------------------


def extract_meta(soup: BeautifulSoup, key: str) -> Optional[str]:
    """Return the ``content`` of the first meta tag matching ``key``.

    Matches ``<meta property="key">`` *and* ``<meta name="key">`` so
    OpenGraph, Twitter and standard meta tags are treated uniformly.

    Args:
        soup: Source :class:`BeautifulSoup`.
        key: Meta key to look up (case-insensitive, e.g. ``"og:image"``).

    Returns:
        The ``content`` attribute, or ``None`` when no match.
    """
    if soup is None or not key:
        return None
    needle = key.strip().lower()
    for meta in soup.find_all("meta"):
        if not isinstance(meta, Tag):
            continue
        for attr in ("property", "name", "itemprop"):
            value = meta.get(attr)
            if value and str(value).strip().lower() == needle:
                content = meta.get("content")
                if content is not None and str(content).strip():
                    return str(content).strip()
    return None


def extract_all_meta(
    soup: BeautifulSoup, key: str
) -> List[str]:
    """Return every ``content`` value for meta tags matching ``key``."""
    if soup is None or not key:
        return []
    needle = key.strip().lower()
    results: List[str] = []
    for meta in soup.find_all("meta"):
        if not isinstance(meta, Tag):
            continue
        for attr in ("property", "name", "itemprop"):
            value = meta.get(attr)
            if value and str(value).strip().lower() == needle:
                content = meta.get("content")
                if content is not None and str(content).strip():
                    results.append(str(content).strip())
    return results


# ---------------------------------------------------------------------------
# Misc utilities
# ---------------------------------------------------------------------------


def first_attr(*values: Optional[str]) -> Optional[str]:
    """Return the first non-empty ``values`` element, or ``None``."""
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


def deduplicate_lines(text: str) -> str:
    """Drop consecutive duplicate lines from ``text``."""
    if not text:
        return ""
    seen: set[str] = set()
    lines: List[str] = []
    for raw in text.splitlines():
        key = _WS_RE.sub(" ", raw.strip().lower())
        if not key:
            continue
        if key in seen:
            continue
        seen.add(key)
        lines.append(raw.strip())
    return " ".join(lines)


__all__ = [
    "parse_html",
    "strip_noise",
    "extract_text",
    "find_section",
    "find_faq_pairs",
    "find_definition_pairs",
    "extract_meta",
    "extract_all_meta",
    "first_attr",
    "deduplicate_lines",
]