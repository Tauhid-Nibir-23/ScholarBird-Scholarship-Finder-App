"""Small, dependency-free helper functions used across the backend.

These functions are intentionally tiny and side-effect-free so they
remain trivial to unit-test in later phases.
"""

from __future__ import annotations

import re
from typing import Any, Iterable, Iterator, List, Optional, TypeVar

T = TypeVar("T")


def chunked(items: Iterable[T], size: int) -> Iterator[List[T]]:
    """Yield successive chunks of ``items`` with at most ``size`` elements.

    Args:
        items: Source iterable.
        size: Maximum size of each chunk. Must be ``>= 1``.

    Yields:
        Lists of at most ``size`` elements.

    Raises:
        ValueError: If ``size`` is less than 1.
    """
    if size < 1:
        raise ValueError("chunk size must be >= 1")
    chunk: List[T] = []
    for item in items:
        chunk.append(item)
        if len(chunk) >= size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def safe_get(mapping: Optional[dict], *keys: str, default: Any = None) -> Any:
    """Look up nested keys in a dict without raising ``KeyError``.

    Args:
        mapping: Optional source mapping. ``None`` returns ``default``.
        keys: Sequence of keys forming a nested path.
        default: Value returned when any segment is missing.

    Returns:
        The looked-up value or ``default``.
    """
    current: Any = mapping
    for key in keys:
        if not isinstance(current, dict):
            return default
        if key not in current:
            return default
        current = current[key]
    return current


def coalesce(*values: Optional[T], default: Optional[T] = None) -> Optional[T]:
    """Return the first non-``None`` value or ``default``.

    Args:
        *values: Candidate values, in priority order.
        default: Fallback value.

    Returns:
        The first non-``None`` value, otherwise ``default``.
    """
    for value in values:
        if value is not None:
            return value
    return default


def truncate(text: Optional[str], limit: int) -> str:
    """Trim ``text`` to ``limit`` characters, appending an ellipsis.

    Args:
        text: Optional source string.
        limit: Maximum length. Must be ``>= 0``.

    Returns:
        Possibly truncated string.
    """
    if limit < 0:
        raise ValueError("limit must be >= 0")
    if text is None:
        return ""
    if len(text) <= limit:
        return text
    if limit == 0:
        return ""
    return text[: limit - 1].rstrip() + "…"


_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(text: Optional[str]) -> str:
    """Convert ``text`` to a URL-safe lowercase slug.

    Args:
        text: Optional input string.

    Returns:
        A slug composed of ``[a-z0-9-]`` separated by single hyphens.
    """
    if not text:
        return ""
    normalized = text.lower().strip()
    slug = _SLUG_RE.sub("-", normalized).strip("-")
    return slug