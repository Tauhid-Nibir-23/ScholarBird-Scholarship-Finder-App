"""Robust, additive image extraction.

This module is a **drop-in upgrade** to :mod:`backend.parser.extractors.image`.
It is consumed by :mod:`backend.parser.enrich` as an *additional* fallback that
runs only when the legacy regex and the modern engine have already produced
nothing — it never replaces either path and never overwrites a scraper-supplied
``Scholarship.image``.

Design goals
------------
1. ``<picture>`` and ``<source srcset>`` parsing (multi-format art direction).
2. ``<img srcset>`` parsing with the highest-quality candidate selected.
3. Hero / banner / featured CSS class whitelist that understands the
   vocabulary real scholarship landing pages use.
4. Ranking that puts validated hero / featured images above generic
   ``<meta name="image">`` values.
5. Optional :func:`validate_image_url` HEAD probe when a fetcher is available.
6. HTTPS-only filtering, extension filtering, and duplicate removal — all
   inherited from the existing :mod:`image` module.

The module is **purely additive**: it does not import from any module that
imports from it, and it does not mutate global state. Every function is
safe to call from the enricher as a pure function.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Iterable, List, Optional, Tuple
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup, Tag

from .image import (
    _BAD_EXTENSIONS,
    _push,
    validate_image_url,
)


logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


#: CSS class tokens that identify a hero / banner / featured image on real
#: scholarship landing pages. List is intentionally broader than the one
#: hard-coded in :mod:`image` so that DAAD, Erasmus Mundus, Chevening, and
#: other publishers with their own design systems are covered.
HERO_CLASS_TOKENS: Tuple[str, ...] = (
    "hero",
    "hero-image",
    "banner",
    "cover",
    "cover-image",
    "featured",
    "featured-image",
    "lead",
    "lead-image",
    "program-image",
    "scholarship-image",
    "article-image",
    "thumbnail",
)


#: Regex used to split a ``srcset`` attribute into ``(url, descriptor)``
#: pairs. The descriptor is either a width (``480w``) or a pixel density
#: (``2x``); we use it to pick the highest-quality candidate.
#:
#: The URL portion is greedy up to the next whitespace before an
#: optional descriptor; trailing commas are consumed by the splitter.
_SRCSET_RE = re.compile(
    r"\s*(?P<url>[^,\s]+)(?:\s+(?P<desc>\d+w|[\d.]+x))?",
    re.IGNORECASE,
)


#: Default width threshold (CSS pixels) for ranking a ``srcset`` entry whose
#: descriptor is a pixel density. ``2x`` on a 480px slot wins over ``1x``.
_DENSITY_VIEWPORT_PX = 480


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class RobustImageResult:
    """Ranked image candidates from the robust extractor.

    Attributes:
        candidates: Ordered candidate URLs (best first).
        evidence: Human-readable ``source::url`` entries matched 1:1 with
            ``candidates``. The first element is the same value that
            :attr:`best` returns.
    """

    candidates: List[str] = field(default_factory=list)
    evidence: List[str] = field(default_factory=list)

    @property
    def best(self) -> Optional[str]:
        """Return the first candidate or ``None``."""
        return self.candidates[0] if self.candidates else None

    def is_empty(self) -> bool:
        return not self.candidates


# ---------------------------------------------------------------------------
# srcset helpers
# ---------------------------------------------------------------------------


def _parse_srcset(value: str) -> List[Tuple[str, float]]:
    """Parse a ``srcset`` attribute into a list of ``(url, score)`` pairs.

    The ``score`` is the larger of:

    * the width descriptor (e.g. ``1024w`` → ``1024.0``), or
    * the pixel density × :data:`_DENSITY_VIEWPORT_PX`
      (e.g. ``2x`` → ``960.0``).

    Higher scores win. The function tolerates trailing commas and
    whitespace and never raises on malformed input.
    """
    if not value:
        return []
    # Strip trailing/leading commas and whitespace to keep the
    # boundary-detection regex straightforward.
    cleaned = value.strip().strip(",")
    pairs: List[Tuple[str, float]] = []
    for match in _SRCSET_RE.finditer(cleaned):
        url = match.group("url")
        descriptor = (match.group("desc") or "").lower()
        if not url:
            continue
        score = 0.0
        if descriptor.endswith("w"):
            try:
                score = float(descriptor[:-1])
            except ValueError:
                score = 0.0
        elif descriptor.endswith("x"):
            try:
                score = float(descriptor[:-1]) * _DENSITY_VIEWPORT_PX
            except ValueError:
                score = 0.0
        pairs.append((url, score))
    return pairs


def _best_srcset(value: str, *, base: Optional[str] = None) -> Optional[str]:
    """Return the best URL from a ``srcset`` attribute, or ``None``."""
    pairs = _parse_srcset(value)
    if not pairs:
        return None
    pairs.sort(key=lambda item: item[1], reverse=True)
    return pairs[0][0]


# ---------------------------------------------------------------------------
# <picture> and <source srcset>
# ---------------------------------------------------------------------------


def _gather_picture(
    soup: BeautifulSoup,
    base: Optional[str],
    candidates: List[str],
    seen: set[str],
    evidence: List[str],
) -> None:
    """Pull the best URL from every ``<picture>`` block.

    The browser picks from ``<source srcset>`` first, then falls back to
    the ``<img>`` inside the ``<picture>``. We mirror that order — the
    highest-quality ``<source srcset>`` candidate wins, and the inner
    ``<img>`` only fills the gap if no source carried a URL.
    """
    if soup is None:
        return
    for picture in soup.find_all("picture"):
        if not isinstance(picture, Tag):
            continue
        # 1. Highest-quality <source srcset> across the entire picture.
        best_source: Optional[str] = None
        best_score: float = -1.0
        for source in picture.find_all("source"):
            if not isinstance(source, Tag):
                continue
            srcset = source.get("srcset") or source.get("data-srcset")
            if not srcset:
                continue
            for url, score in _parse_srcset(str(srcset)):
                if score > best_score:
                    best_score = score
                    best_source = url
        if best_source:
            _push(
                candidates,
                seen,
                best_source,
                base,
                evidence,
                "picture:source",
            )

        # 2. Inner <img> as a fallback (only if no source matched).
        if best_source is None:
            inner = picture.find("img")
            if isinstance(inner, Tag):
                src = (
                    inner.get("src")
                    or inner.get("data-src")
                    or inner.get("data-lazy-src")
                )
                if src:
                    _push(
                        candidates,
                        seen,
                        str(src),
                        base,
                        evidence,
                        "picture:img",
                    )


def _gather_srcset(
    soup: BeautifulSoup,
    base: Optional[str],
    candidates: List[str],
    seen: set[str],
    evidence: List[str],
) -> None:
    """Pick the highest-quality entry from every ``srcset`` attribute."""
    if soup is None:
        return
    for element in soup.find_all(attrs={"srcset": True}):
        if not isinstance(element, Tag):
            continue
        srcset = element.get("srcset")
        if not srcset:
            continue
        best = _best_srcset(str(srcset), base=base)
        if best:
            _push(candidates, seen, best, base, evidence, "srcset")


# ---------------------------------------------------------------------------
# Hero / featured recognition
# ---------------------------------------------------------------------------


def _class_blob(tag: Tag) -> str:
    """Return a lowercase ``class`` + ``id`` + ``role`` blob for a tag."""
    return " ".join(
        filter(
            None,
            [
                " ".join(tag.get("class") or []),
                str(tag.get("id") or ""),
                str(tag.get("role") or ""),
            ],
        )
    ).lower()


def _is_hero(tag: Tag) -> bool:
    """Return ``True`` when ``tag`` (or any ancestor) carries a hero class."""
    if not isinstance(tag, Tag):
        return False
    for node in [tag, *tag.parents]:
        if not isinstance(node, Tag):
            continue
        blob = _class_blob(node)
        if any(token in blob for token in HERO_CLASS_TOKENS):
            return True
    return False


def _gather_hero(
    soup: BeautifulSoup,
    base: Optional[str],
    candidates: List[str],
    seen: set[str],
    evidence: List[str],
) -> None:
    """Collect URLs from every ``<img>`` whose class tree says "hero".

    The ``srcset`` candidate is preferred over the plain ``src`` because
    the highest-quality descriptor usually wins over the smallest
    pre-resolved fallback URL.
    """
    if soup is None:
        return
    for img in soup.find_all("img"):
        if not isinstance(img, Tag):
            continue
        if not _is_hero(img):
            continue
        srcset = img.get("srcset")
        if srcset:
            best = _best_srcset(str(srcset), base=base)
            if best:
                _push(
                    candidates, seen, best, base, evidence, "hero-srcset"
                )
        src = (
            img.get("src")
            or img.get("data-src")
            or img.get("data-lazy-src")
        )
        if src:
            _push(candidates, seen, str(src), base, evidence, "hero-class")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


_NOISE_TAGS: Tuple[str, ...] = ("script", "style", "noscript", "iframe")


def _local_strip_noise(soup: BeautifulSoup) -> BeautifulSoup:
    """Defensive local copy that only drops chrome tag blocks.

    The project-wide :func:`html.strip_noise` removes elements whose
    class/id screams "navigation/footer/etc."; that helper trips on
    ``None`` elements produced by some malformed markup. The robust
    extractor only needs to ignore ``<script>`` / ``<style>`` so we
    perform the trivial pass in-place.
    """
    if soup is None:
        return BeautifulSoup("", "html.parser")
    tree = BeautifulSoup(str(soup), "html.parser")
    for tag in tree.find_all(_NOISE_TAGS):
        tag.decompose()
    return tree


def extract_robust_images(
    soup: BeautifulSoup,
    page_url: Optional[str] = None,
    *,
    fetcher: Optional[object] = None,
    validate: bool = False,
) -> RobustImageResult:
    """Return ranked, optionally validated image candidates.

    The function is additive: it reuses :func:`validate_image_url` and
    :func:`_push` from the existing :mod:`image` module so HTTPS filtering,
    extension filtering, and duplicate removal behave identically.

    Args:
        soup: Source :class:`BeautifulSoup`.
        page_url: The final URL the page was loaded from. Used to resolve
            relative URLs.
        fetcher: Optional network fetcher passed to
            :func:`validate_image_url` when ``validate=True`` — typically
            the enricher's shared ``httpx.Client``.
        validate: When ``True`` (default ``False``), every candidate is
            probed with a HEAD request and rejected when the response
            content-type is not ``image/*``. The enricher layer decides
            whether to opt in.

    Returns:
        A :class:`RobustImageResult` whose :attr:`best` is the highest-
        ranked surviving URL.
    """
    result = RobustImageResult()
    if soup is None:
        return result

    cleaned = _local_strip_noise(soup)
    seen: set[str] = set()

    # Order matters: <picture>/<source srcset> first (browser-faithful),
    # then hero class recognition, then plain srcset, then generic <img>.
    _gather_picture(cleaned, page_url, result.candidates, seen, result.evidence)
    _gather_hero(cleaned, page_url, result.candidates, seen, result.evidence)
    _gather_srcset(cleaned, page_url, result.candidates, seen, result.evidence)

    if not validate:
        return result

    # Validation path: keep only URLs that pass validate_image_url.
    validated: List[str] = []
    validated_evidence: List[str] = []
    for url, source in zip(result.candidates, result.evidence):
        ok, final = validate_image_url(url, fetcher=fetcher)
        if ok and final:
            validated.append(final)
            validated_evidence.append(source)
    result.candidates = validated
    result.evidence = validated_evidence
    return result


def pick_best(
    candidates: Iterable[str],
    *,
    fetcher: Optional[object] = None,
    validate: bool = False,
) -> Optional[str]:
    """Return the first candidate that survives validation, or ``None``.

    The helper is provided so the enricher can adopt the robust pick logic
    without coupling to the full :class:`RobustImageResult` dataclass.
    """
    for url in candidates:
        if not url:
            continue
        if not validate:
            return url
        ok, final = validate_image_url(url, fetcher=fetcher)
        if ok and final:
            return final
    return None


__all__ = [
    "HERO_CLASS_TOKENS",
    "RobustImageResult",
    "extract_robust_images",
    "parse_srcset",
    "pick_best",
]


# ---------------------------------------------------------------------------
# Compatibility alias — the public name is exported above; this alias keeps
# any external caller that asked for ``parse_srcset`` working.
# ---------------------------------------------------------------------------


def parse_srcset(value: str) -> List[Tuple[str, float]]:
    """Backwards-compatible alias for :func:`_parse_srcset`."""
    return _parse_srcset(value)
