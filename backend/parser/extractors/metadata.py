"""Unified meta-tag reader.

Pages today use three competing meta conventions:

* ``<meta property="og:*">`` — OpenGraph (Facebook)
* ``<meta name="twitter:*">`` — Twitter Cards
* ``<meta name="...">`` — classic meta tags (``description``, ``author``…)

This module funnels all three into a single dict-like object so other
extractors can ask for ``meta.title`` and get the best answer the page
provides — never the first answer regardless of quality.

Priority rules:

* For OpenGraph-style properties (``og:*``): the highest-quality value
  is the one whose key is most specific (e.g. ``og:title`` beats
  ``og:site_name`` for the title slot).
* For Twitter-style properties (``twitter:*``): same rule — only used
  when no OpenGraph value is present, because OG is more widely
  supported.
* For standard tags: ``<meta name="...">`` is read only as a fallback.

The module exposes a :class:`PageMetadata` dataclass — the canonical
data shape consumed by ``engine.py`` and the rest of the extractor
package.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from bs4 import BeautifulSoup

from .html import extract_all_meta, extract_meta


# ---------------------------------------------------------------------------
# Data shape
# ---------------------------------------------------------------------------


@dataclass
class PageMetadata:
    """Aggregate of all meta values present in the page.

    The dataclass is intentionally flat: every field has the same
    precedence — first-non-empty wins, where sources are tried in
    priority order (OG → Twitter → standard → heuristics).
    """

    title: Optional[str] = None
    description: Optional[str] = None
    image: Optional[str] = None
    image_alt: Optional[str] = None
    site_name: Optional[str] = None
    type: Optional[str] = None
    url: Optional[str] = None
    locale: Optional[str] = None
    author: Optional[str] = None
    keywords: List[str] = field(default_factory=list)
    twitter_card: Optional[str] = None
    raw_og: Dict[str, str] = field(default_factory=dict)
    raw_twitter: Dict[str, str] = field(default_factory=dict)
    raw_standard: Dict[str, str] = field(default_factory=dict)

    def is_empty(self) -> bool:
        """Return ``True`` when no field contains useful content."""
        for name, value in self.__dict__.items():
            if name in ("raw_og", "raw_twitter", "raw_standard", "keywords"):
                continue
            if value:
                return False
        return not (self.raw_og or self.raw_twitter or self.raw_standard)


# ---------------------------------------------------------------------------
# OpenGraph keys
# ---------------------------------------------------------------------------

#: Mapping from semantic slot → list of OG keys to try (in order).
_OG_KEYS: Dict[str, List[str]] = {
    "title": ["og:title"],
    "description": ["og:description"],
    "image": ["og:image", "og:image:secure_url", "og:image:url"],
    "image_alt": ["og:image:alt"],
    "site_name": ["og:site_name"],
    "type": ["og:type"],
    "url": ["og:url"],
    "locale": ["og:locale"],
}

#: Standard meta names we recognise.
_STANDARD_KEYS: Dict[str, List[str]] = {
    "title": ["title"],
    "description": ["description", "DC.description", "dcterms.description"],
    "image": ["image"],
    "author": ["author", "DC.creator", "article:author"],
    "keywords": ["keywords", "news_keywords"],
}

#: Twitter-card keys recognised.
_TWITTER_KEYS: Dict[str, List[str]] = {
    "title": ["twitter:title"],
    "description": ["twitter:description"],
    "image": ["twitter:image", "twitter:image:src"],
    "card": ["twitter:card"],
    "site": ["twitter:site"],
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _collect(
    soup: BeautifulSoup, keys: List[str]
) -> tuple[Optional[str], Dict[str, str]]:
    """Walk ``keys`` in order; return ``(first_hit, full_map)``."""
    full: Dict[str, str] = {}
    chosen: Optional[str] = None
    for key in keys:
        values = extract_all_meta(soup, key)
        for value in values:
            full.setdefault(key, value)
        for value in values:
            if chosen is None:
                chosen = value
            return chosen, full
    return chosen, full


def _collect_all(
    soup: BeautifulSoup, keys: List[str]
) -> Dict[str, str]:
    """Collect every key/value pair for a family of meta tags."""
    full: Dict[str, str] = {}
    for key in keys:
        values = extract_all_meta(soup, key)
        if values:
            full[key] = values[0]
    return full


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_metadata(soup: BeautifulSoup) -> PageMetadata:
    """Return a populated :class:`PageMetadata` instance.

    Precedence for each field:

    1. OpenGraph (``og:*``) — preferred when available.
    2. Twitter Card (``twitter:*``).
    3. Standard ``<meta name>`` tags.
    4. ``<title>`` element (title slot only).

    The function never invents values: if the page lacks a value for
    a slot, the slot remains ``None`` (or ``[]`` for lists).

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        A :class:`PageMetadata` with every readable slot populated.
    """
    meta = PageMetadata()

    # 1. OpenGraph — primary source.
    og_full = _collect_all(soup, sum(_OG_KEYS.values(), []))
    meta.raw_og = dict(og_full)
    for slot, keys in _OG_KEYS.items():
        value = next((og_full[k] for k in keys if k in og_full), None)
        if value is not None:
            setattr(meta, slot, value)

    # 2. Twitter Cards — fill slots the OG didn't set.
    tw_full = _collect_all(soup, sum(_TWITTER_KEYS.values(), []))
    meta.raw_twitter = dict(tw_full)
    for slot, keys in _TWITTER_KEYS.items():
        target = slot if slot != "card" else "twitter_card"
        target = "site_name" if slot == "site" else target
        if getattr(meta, target) is None:
            value = next(
                (tw_full[k] for k in keys if k in tw_full), None
            )
            if value is not None:
                setattr(meta, target, value)

    # 3. Standard <meta name>.
    std_full = _collect_all(soup, sum(_STANDARD_KEYS.values(), []))
    meta.raw_standard = dict(std_full)
    for slot, keys in _STANDARD_KEYS.items():
        value = next(
            (std_full[k] for k in keys if k in std_full), None
        )
        if value is None:
            continue
        if slot == "keywords":
            meta.keywords = [
                token.strip()
                for token in re_split_keywords(value)
                if token.strip()
            ]
        elif getattr(meta, slot) is None:
            setattr(meta, slot, value)

    # 4. <title> tag is the last-resort title source.
    if not meta.title:
        title_node = soup.find("title") if soup is not None else None
        if title_node is not None:
            meta.title = title_node.get_text(separator=" ", strip=True)

    return meta


def re_split_keywords(value: str) -> List[str]:
    """Split a ``keywords`` value on commas or whitespace."""
    if not value:
        return []
    tokens: List[str] = []
    for piece in value.replace(",", " ").split():
        piece = piece.strip()
        if piece and piece not in tokens:
            tokens.append(piece)
    return tokens


__all__ = ["PageMetadata", "extract_metadata"]
