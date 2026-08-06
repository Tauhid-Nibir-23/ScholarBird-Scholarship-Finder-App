"""Tests for the additive robust image extractor.

The tests run without any network access. The fetcher is mocked to
simulate HEAD probes so the validation path can be exercised in-process.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Ensure the project root is on ``sys.path`` so ``import backend.*`` works
# regardless of the working directory, mirroring the existing test files.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from bs4 import BeautifulSoup

from backend.parser.extractors.html import parse_html
from backend.parser.extractors.image_robust import (
    HERO_CLASS_TOKENS,
    RobustImageResult,
    extract_robust_images,
    parse_srcset,
    pick_best,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make(html: str) -> BeautifulSoup:
    return parse_html(html)


def _ok_fetcher(url: str) -> dict:
    """Pretend every URL returns an image content-type."""
    return {
        "status_code": 200,
        "content_type": "image/jpeg",
        "final_url": url,
    }


def _bad_fetcher(url: str) -> dict:
    """Pretend every URL returns HTML (not an image)."""
    return {
        "status_code": 200,
        "content_type": "text/html",
        "final_url": url,
    }


# ---------------------------------------------------------------------------
# srcset parser
# ---------------------------------------------------------------------------


def test_parse_srcset_width_descriptors() -> None:
    pairs = parse_srcset(
        "small.jpg 480w, medium.jpg 1024w, large.jpg 2048w"
    )
    urls = [url for url, _ in pairs]
    assert urls == ["small.jpg", "medium.jpg", "large.jpg"]
    scores = [score for _, score in pairs]
    assert scores == [480.0, 1024.0, 2048.0]
    assert max(scores) == 2048.0


def test_parse_srcset_density_descriptors() -> None:
    pairs = parse_srcset("normal.jpg 1x, retina.jpg 2x")
    scores = [score for _, score in pairs]
    assert scores[0] == 480.0  # 1 * 480
    assert scores[1] == 960.0  # 2 * 480


def test_parse_srcset_empty_or_garbage() -> None:
    assert parse_srcset("") == []
    assert parse_srcset("   ") == []
    assert parse_srcset(",,,") == []


# ---------------------------------------------------------------------------
# <picture> and <source srcset>
# ---------------------------------------------------------------------------


def test_picture_source_srcset_wins() -> None:
    html = """
    <picture>
      <source srcset="hero-1x.jpg 1x, hero-2x.jpg 2x" type="image/jpeg">
      <img src="hero-fallback.jpg" alt="hero">
    </picture>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.best == "https://example.com/hero-2x.jpg"


def test_picture_falls_back_to_inner_img() -> None:
    html = """
    <picture>
      <img src="hero-fallback.jpg" alt="hero">
    </picture>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.best == "https://example.com/hero-fallback.jpg"


def test_srcset_standalone_img() -> None:
    html = """
    <img src="tiny.jpg"
         srcset="small.jpg 480w, medium.jpg 1024w, large.jpg 2048w"
         alt="banner">
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.best == "https://example.com/large.jpg"


# ---------------------------------------------------------------------------
# Hero / featured class whitelist
# ---------------------------------------------------------------------------


def test_hero_class_recognition() -> None:
    for token in HERO_CLASS_TOKENS:
        html = f"""
        <img class="{token}" src="https://example.com/{token}.jpg">
        """
        result = extract_robust_images(
            _make(html), page_url="https://example.com"
        )
        assert result.best == f"https://example.com/{token}.jpg", (
            f"failed for token {token}"
        )


def test_hero_class_ancestor_match() -> None:
    html = """
    <div class="featured-image">
      <figure>
        <img src="https://example.com/nested.jpg">
      </figure>
    </div>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.best == "https://example.com/nested.jpg"


def test_hero_srcset_picked() -> None:
    html = """
    <div class="hero-banner">
      <img src="https://example.com/small.jpg"
           srcset="https://example.com/med.jpg 1024w,
                   https://example.com/large.jpg 2048w">
    </div>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.best == "https://example.com/large.jpg"


# ---------------------------------------------------------------------------
# HTTPS / extension / dedupe
# ---------------------------------------------------------------------------


def test_http_scheme_rejected() -> None:
    html = """
    <picture>
      <source srcset="http://example.com/hero.jpg">
    </picture>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.is_empty() or all(
        url.startswith("https://") for url in result.candidates
    )


def test_bad_extension_rejected() -> None:
    html = """
    <div class="hero">
      <img src="https://example.com/page.html">
      <img src="https://example.com/hero.jpg">
    </div>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert "https://example.com/hero.jpg" in result.candidates
    assert "https://example.com/page.html" not in result.candidates


def test_duplicate_removal() -> None:
    html = """
    <picture>
      <source srcset="https://example.com/hero.jpg 1x,
                       https://example.com/hero.jpg 2x">
    </picture>
    <div class="hero">
      <img src="https://example.com/hero.jpg">
    </div>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.candidates.count("https://example.com/hero.jpg") == 1


# ---------------------------------------------------------------------------
# Validation with mocked fetcher
# ---------------------------------------------------------------------------


def test_validation_keeps_image_responses() -> None:
    html = """
    <picture>
      <source srcset="https://example.com/hero.jpg">
    </picture>
    """
    result = extract_robust_images(
        _make(html),
        page_url="https://example.com",
        fetcher=_ok_fetcher,
        validate=True,
    )
    assert result.best == "https://example.com/hero.jpg"


def test_validation_drops_html_responses() -> None:
    html = """
    <picture>
      <source srcset="https://example.com/hero.jpg">
    </picture>
    """
    result = extract_robust_images(
        _make(html),
        page_url="https://example.com",
        fetcher=_bad_fetcher,
        validate=True,
    )
    assert result.is_empty()


def test_pick_best_without_validation() -> None:
    assert pick_best(["https://example.com/a.jpg"]) == "https://example.com/a.jpg"


def test_pick_best_with_validation() -> None:
    assert (
        pick_best(
            ["https://example.com/a.jpg", "https://example.com/b.jpg"],
            fetcher=_ok_fetcher,
            validate=True,
        )
        == "https://example.com/a.jpg"
    )


# ---------------------------------------------------------------------------
# Backwards compatibility
# ---------------------------------------------------------------------------


def test_robust_dataclass_is_empty_when_no_candidates() -> None:
    result = RobustImageResult()
    assert result.is_empty()
    assert result.best is None


def test_no_html_returns_empty() -> None:
    result = extract_robust_images(_make(""))
    assert result.is_empty()


def test_picture_source_then_hero_class_order() -> None:
    """When both exist, the <picture> winner still ranks first."""
    html = """
    <picture>
      <source srcset="https://example.com/picture.jpg">
    </picture>
    <div class="hero">
      <img src="https://example.com/hero.jpg">
    </div>
    """
    result = extract_robust_images(_make(html), page_url="https://example.com")
    assert result.candidates[0] == "https://example.com/picture.jpg"
    assert "https://example.com/hero.jpg" in result.candidates
