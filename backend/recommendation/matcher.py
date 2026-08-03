"""Small deterministic matching primitives."""

from __future__ import annotations

from typing import Any


def normalise(value: Any) -> str:
    return " ".join(str(value or "").casefold().replace("-", " ").split())


def matches(expected: Any, actual: Any) -> bool:
    """Return true for equal values or an explicit field/tag inclusion."""
    left, right = normalise(expected), normalise(actual)
    degree_aliases = {
        "masters": "postgraduate", "master": "postgraduate", "graduate": "postgraduate",
        "phd": "phd", "doctoral": "phd", "doctorate": "phd",
        "bachelor": "bachelors", "undergraduate": "bachelors",
    }
    left, right = degree_aliases.get(left, left), degree_aliases.get(right, right)
    return bool(left and right and (left == right or left in right or right in left))


def scholarship_value(record: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if record.get(key) not in (None, ""):
            return record[key]
    return None
