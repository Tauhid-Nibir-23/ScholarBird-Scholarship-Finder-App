"""OpenGraph and Twitter Card extraction.

JSON-LD is higher quality than the OpenGraph protocol — see
``jsonld.py``. These helpers exist so that pages lacking JSON-LD (and
there are many) still feed meaningful values to the engine.

The module exposes a single :func:`extract_opengraph` function that
returns an :class:`OgFields` dataclass. It uses
:func:`html.extract_all_meta` under the hood, but normalises the most
common variations:

* ``og:image`` may be a URL string, a list of URLs, or an array of
  image dicts (``{"url": "..."}``). We always return a list of strings.
* ``og:locale`` may be ``"en_US"`` or ``"en-us"``; we keep the raw form
  but expose a ``language`` field that extracts just the leading two
  characters.

Twitter Cards are collected into a small dict; the engine pulls from
OG first and falls back to Twitter when the OG slot is empty.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from bs4 import BeautifulSoup

from .html import extract_all_meta


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class OgFields:
    """Curated values from OpenGraph and Twitter Card meta tags."""

    title: Optional[str] = None
    description: Optional[str] = None
    image: List[str] = field(default_factory=list)
    image_alt: List[str] = field(default_factory=list)
    site_name: Optional[str] = None
    type: Optional[str] = None
    url: Optional[str] = None
    locale: Optional[str] = None
    language: Optional[str] = None
    twitter_card: Optional[str] = None
    twitter_site: Optional[str] = None
    twitter_title: Optional[str] = None
    twitter_description: Optional[str] = None
    twitter_image: List[str] = field(default_factory=list)
    extra_og: Dict[str, str] = field(default_factory=dict)
    extra_twitter: Dict[str, str] = field(default_factory=dict)

    def first_image(self) -> Optional[str]:
        """Return the first image URL or ``None``."""
        return self.image[0] if self.image else None

    def first_twitter_image(self) -> Optional[str]:
        """Return the first Twitter image or ``None``."""
        return self.twitter_image[0] if self.twitter_image else None

    def is_empty(self) -> bool:
        """Return ``True`` when no value was found."""
        for name, value in self.__dict__.items():
            if name in (
                "extra_og",
                "extra_twitter",
                "image",
                "image_alt",
                "twitter_image",
            ):
                continue
            if value:
                return False
        return not (self.extra_og or self.extra_twitter)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


_LANG_RE = re.compile(r"^([a-zA-Z]{2,3})")


def _coerce_locale(locale: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    """Split an OpenGraph locale into ``(locale, language)``."""
    if not locale:
        return None, None
    text = locale.strip()
    match = _LANG_RE.match(text)
    language = match.group(1).lower() if match else None
    return text or None, language


def extract_opengraph(soup: BeautifulSoup) -> OgFields:
    """Read OpenGraph and Twitter meta tags off ``soup``.

    The function always returns an :class:`OgFields` instance —
    empty when no meta tags were found, populated otherwise.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        A populated :class:`OgFields`.
    """
    og = OgFields()
    if soup is None:
        return og

    # Collect every meta property we recognise, dedupe via dict semantics.
    for key in extract_all_meta(soup, "og:title"):
        og.title = key
        break
    for key in extract_all_meta(soup, "og:description"):
        og.description = key
        break
    for key in extract_all_meta(soup, "og:site_name"):
        og.site_name = key
        break
    for key in extract_all_meta(soup, "og:type"):
        og.type = key
        break
    for key in extract_all_meta(soup, "og:url"):
        og.url = key
        break

    # og:locale — keep raw + lowercase language code.
    locale, language = _coerce_locale(
        next(iter(extract_all_meta(soup, "og:locale")), None)
    )
    og.locale = locale
    og.language = language

    # og:image can be a URL string, an array, or repeated meta tags.
    seen: set[str] = set()
    for value in extract_all_meta(soup, "og:image"):
        og.extra_og.setdefault("og:image", value)
        if value not in seen:
            seen.add(value)
            og.image.append(value)
    for value in extract_all_meta(soup, "og:image:secure_url"):
        og.extra_og.setdefault("og:image:secure_url", value)
        if value not in seen:
            seen.add(value)
            og.image.append(value)
    for value in extract_all_meta(soup, "og:image:url"):
        og.extra_og.setdefault("og:image:url", value)
        if value not in seen:
            seen.add(value)
            og.image.append(value)

    for value in extract_all_meta(soup, "og:image:alt"):
        og.extra_og.setdefault("og:image:alt", value)
        if value not in og.image_alt:
            og.image_alt.append(value)

    # Capture every other og:* key verbatim — useful for taxonomy.
    for meta in soup.find_all("meta"):
        if not meta.get("property"):
            continue
        property_name = str(meta.get("property")).strip()
        if not property_name.lower().startswith("og:"):
            continue
        if property_name.lower() in {
            "og:title",
            "og:description",
            "og:site_name",
            "og:type",
            "og:url",
            "og:locale",
            "og:image",
            "og:image:secure_url",
            "og:image:url",
            "og:image:alt",
        }:
            continue
        content = meta.get("content")
        if content:
            og.extra_og.setdefault(property_name, str(content).strip())

    # Twitter card fill.
    for value in extract_all_meta(soup, "twitter:card"):
        og.twitter_card = value
        break
    for value in extract_all_meta(soup, "twitter:site"):
        og.twitter_site = value
        break
    for value in extract_all_meta(soup, "twitter:title"):
        og.twitter_title = value
        og.extra_twitter.setdefault("twitter:title", value)
        break
    for value in extract_all_meta(soup, "twitter:description"):
        og.twitter_description = value
        og.extra_twitter.setdefault("twitter:description", value)
        break
    for value in (
        extract_all_meta(soup, "twitter:image")
        + extract_all_meta(soup, "twitter:image:src")
    ):
        og.extra_twitter.setdefault("twitter:image", value)
        if value not in og.twitter_image:
            og.twitter_image.append(value)

    return og


__all__ = ["OgFields", "extract_opengraph"]
