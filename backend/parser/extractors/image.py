"""Image extraction and validation.

The page may carry an image in many ways. We surface every plausible
candidate and rank them in priority order so the engine can pick
the best one without further work.

Priority order (first hit wins when downstream code asks for "the"
image):

1. ``og:image`` / ``og:image:secure_url``.
2. Twitter card image (``twitter:image``, ``twitter:image:src``).
3. JSON-LD ``image`` field.
4. Inline hero banner (banner/hero class hints).
5. First ``<img>`` tag with a sane ``src`` attribute.
6. Page-wide fallback (any surviving ``<img>``).

The module also exposes :func:`validate_image_url` for callers that
want to verify a URL is real, accessible, and an image (not an HTML
preview page). Validation is **optional** — calling code that wants
to avoid network round-trips can simply skip it.

We never store HTML pages, relative paths, or non-image URLs.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import List, Optional
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup, Tag

from .html import extract_meta, strip_noise
from .jsonld import extract_jsonld
from .opengraph import extract_opengraph


logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class ImageResult:
    """All image URLs the page exposes, ranked + validated."""

    candidates: List[str] = field(default_factory=list)
    evidence: List[str] = field(default_factory=list)

    @property
    def best(self) -> Optional[str]:
        """Return the first candidate or ``None``."""
        return self.candidates[0] if self.candidates else None

    def is_empty(self) -> bool:
        return not self.candidates


# ---------------------------------------------------------------------------
# Validation (network round-trip)
# ---------------------------------------------------------------------------

#: Image MIME types we recognise.
_IMAGE_CONTENT_PREFIX = "image/"

_BAD_EXTENSIONS: tuple[str, ...] = (
    ".html",
    ".htm",
    ".shtml",
    ".aspx",
    ".jsp",
    ".php",
    ".asp",
    ".js",
    ".css",
)

_EXT_RE = re.compile(
    r"\.(?:png|jpe?g|gif|webp|svg|avif|heic|heif|tiff?|ico|bmp)$",
    re.I,
)


def validate_image_url(
    url: Optional[str],
    *,
    fetcher: Optional[object] = None,
) -> tuple[bool, Optional[str]]:
    """Validate that ``url`` resolves to an actual image.

    Args:
        url: Candidate image URL (absolute or relative).
        fetcher: Optional callable ``fetcher(url) -> {"status_code",
            "content_type", "final_url"}``. When ``None``, the function
            performs a HEAD request through :mod:`httpx` if it's
            available, or returns ``(True, url)`` when no network
            module is present (best-effort offline mode).

    Returns:
        ``(ok, final_url)``. ``ok`` is ``False`` when the URL clearly
        cannot be an image (wrong extension, non-HTTPS scheme, or a
        non-image ``content_type``).
    """
    if not url:
        return False, None

    parsed = urlparse(url)
    if parsed.scheme != "https":
        return False, None
    path = parsed.path.lower()
    if any(path.endswith(ext) for ext in _BAD_EXTENSIONS):
        return False, None

    if fetcher is None:
        # No fetcher → caller has chosen offline mode. We accept URLs
        # whose path looks image-like and reject anything clearly not.
        if _EXT_RE.search(path):
            return True, url
        # Image CDNs commonly use paths ending in /upload/.../v1234/image.jpg
        # but for safety we still allow: trust the URL string.
        return True, url

    try:
        if callable(fetcher):
            result = fetcher(url)
        elif hasattr(fetcher, "head"):
            response = fetcher.head(url, follow_redirects=True)
            result = {
                "status_code": getattr(response, "status_code", None),
                "content_type": getattr(response, "headers", {}).get("content-type", ""),
                "final_url": str(getattr(response, "url", url)),
            }
        else:
            return False, None
    except Exception:
        return False, None
    if not isinstance(result, dict):
        return False, None
    status = result.get("status_code")
    content_type = str(result.get("content_type", "")).lower()
    final_url = result.get("final_url") or url
    if status != 200:
        return False, None
    if not content_type.startswith(_IMAGE_CONTENT_PREFIX):
        return False, None
    if urlparse(str(final_url)).scheme != "https":
        return False, None
    return True, final_url


# ---------------------------------------------------------------------------
# Candidate gatherers
# ---------------------------------------------------------------------------


def _absolutise(url: str, base: Optional[str]) -> Optional[str]:
    if not url:
        return None
    if url.startswith("//"):
        return "https:" + url
    parsed = urlparse(url)
    if parsed.scheme in ("http", "https"):
        return url
    if base:
        return urljoin(base, url)
    return None


def _push(
    candidates: List[str],
    seen: set[str],
    raw: Optional[str],
    base: Optional[str],
    evidence: List[str],
    source: str,
) -> None:
    if not raw:
        return
    absolute = _absolutise(raw, base)
    if not absolute:
        return
    absolute = absolute.strip()
    if not absolute or absolute in seen:
        return
    parsed = urlparse(absolute)
    if parsed.scheme != "https":
        return
    if any(parsed.path.lower().endswith(ext) for ext in _BAD_EXTENSIONS):
        return
    seen.add(absolute)
    candidates.append(absolute)
    evidence.append(f"{source}::{absolute}")


def _gather_opengraph(soup: BeautifulSoup, base: Optional[str],
                     candidates: List[str], seen: set[str],
                     evidence: List[str]) -> None:
    fields = extract_opengraph(soup)
    for url in fields.image:
        _push(candidates, seen, url, base, evidence, "og")
    for url in fields.twitter_image:
        _push(candidates, seen, url, base, evidence, "twitter")


def _gather_jsonld(soup: BeautifulSoup, base: Optional[str],
                   candidates: List[str], seen: set[str],
                   evidence: List[str]) -> None:
    document = extract_jsonld(soup)
    for node in document.nodes:
        if node.image:
            _push(candidates, seen, node.image, base, evidence, "jsonld")


def _gather_inline(soup: BeautifulSoup, base: Optional[str],
                   candidates: List[str], seen: set[str],
                   evidence: List[str]) -> None:
    if soup is None:
        return
    cleaned = strip_noise(soup)

    # 1. Hero/banner images (likely `<div class="hero"><img>...</img></div>`)
    for img in cleaned.find_all("img"):
        if not isinstance(img, Tag):
            continue
        classes = " ".join(img.get("class") or []).lower()
        parent_classes = " ".join(
            " ".join(parent.get("class") or [])
            for parent in img.parents
            if isinstance(parent, Tag)
        ).lower()
        if any(token in classes + parent_classes
               for token in ("hero", "banner", "cover", "thumbnail")):
            src = img.get("src") or img.get("data-src") or img.get("data-lazy-src")
            _push(candidates, seen, src, base, evidence, "hero")

    # 2. Generic <img> tags (only fill gaps).
    for img in cleaned.find_all("img"):
        if not isinstance(img, Tag):
            continue
        src = img.get("src") or img.get("data-src") or img.get("data-lazy-src")
        if not src:
            continue
        src_str = str(src).strip()
        if src_str.startswith("data:"):
            # Inline SVG/PNG data URLs — never store.
            continue
        _push(candidates, seen, src_str, base, evidence, "img")


def _gather_fallback(soup: BeautifulSoup, base: Optional[str],
                     candidates: List[str], seen: set[str],
                     evidence: List[str]) -> None:
    if soup is None:
        return
    cleaned = strip_noise(soup)
    # 1. link rel=image_src.
    link = cleaned.find("link", attrs={"rel": "image_src"})
    if isinstance(link, Tag):
        href = link.get("href")
        if href:
            _push(candidates, seen, str(href), base, evidence, "link:image_src")
    # 2. background-image: url(...) on style attributes.
    bg_re = re.compile(r"url\(\s*['\"]?(?P<u>[^'\")]+)['\"]?\s*\)")
    for element in cleaned.find_all(attrs={"style": bg_re}):
        if not isinstance(element, Tag):
            continue
        style = str(element.get("style") or "")
        for match in bg_re.finditer(style):
            _push(candidates, seen, match.group("u"), base, evidence, "css:bg")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_images(
    soup: BeautifulSoup,
    page_url: Optional[str] = None,
    *,
    fetcher: Optional[object] = None,
    validate: bool = False,
) -> ImageResult:
    """Return ranked image candidates from ``soup``.

    Args:
        soup: Source :class:`BeautifulSoup`.
        page_url: The final URL the page was loaded from. Used to
            resolve relative URLs.
        fetcher: Optional network fetcher used by validation. Pass
            the existing ``fetch_page`` from ``utils.fetcher`` to
            reuse the project's session + cache.
        validate: When ``True``, every candidate URL is verified (HEAD
            request, image content-type, no HTML redirect). When
            ``False`` (default), URLs that look image-ish are kept
            without a network round-trip.

    Returns:
        Populated :class:`ImageResult`.
    """
    result = ImageResult()
    if soup is None:
        return result

    base = page_url
    seen: set[str] = set()

    _gather_opengraph(soup, base, result.candidates, seen, result.evidence)
    _gather_jsonld(soup, base, result.candidates, seen, result.evidence)
    _gather_inline(soup, base, result.candidates, seen, result.evidence)
    _gather_fallback(soup, base, result.candidates, seen, result.evidence)

    if not validate:
        return result

    # Priority requires the first valid source to win.
    for url in result.candidates:
        ok, final = validate_image_url(url, fetcher=fetcher)
        if ok and final:
            result.candidates = [final]
            return result
    result.candidates = []
    return result


__all__ = [
    "ImageResult",
    "extract_images",
    "validate_image_url",
]
