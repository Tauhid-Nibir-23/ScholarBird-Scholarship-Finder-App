"""Validation helpers for normalised scholarship records.

The validator applies a fixed set of rules to a normalised record and
returns a structured :class:`ValidationResult` instead of a bare
``bool``. Callers can therefore log the exact reason a record was
rejected without re-running the checks.

The rule set is intentionally lightweight:

* ``title`` must be non-empty after normalisation.
* ``apply_url`` (when present) must be a valid ``http`` / ``https``
  URL.
* ``link`` (when present) must be a valid URL.
* ``country`` must be non-empty after normalisation.
* ``source`` must be non-empty.
* ``official_id`` is optional.
* ``deadline`` may be ``None`` — the parser already collapses
  "rolling" / "open" / "TBA" / unparseable values to ``None``.
* ``description`` and ``eligibility`` are optional.

Invalid records never crash the pipeline: callers see
``result.is_valid is False`` plus a ``reason`` string they can log.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Dict, Optional

from backend.core.logger import get_logger

_logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# URL detection
# ---------------------------------------------------------------------------

#: Conservative URL pattern. Accepts ``http://`` and ``https://`` only.
_URL_RE = re.compile(r"^https?://[^\s]+$", re.IGNORECASE)


def _is_valid_url(value: Optional[str]) -> bool:
    """Return ``True`` when ``value`` looks like an ``http(s)://`` URL."""
    if not value or not isinstance(value, str):
        return False
    return bool(_URL_RE.match(value.strip()))


# ---------------------------------------------------------------------------
# Result type
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ValidationResult:
    """Outcome of validating a single record.

    Attributes:
        is_valid: ``True`` when every rule passed.
        reason: Human-readable explanation of the first failing rule.
            Empty when ``is_valid`` is ``True``.
    """

    is_valid: bool
    reason: str = ""

    @classmethod
    def ok(cls) -> "ValidationResult":
        """Return a successful :class:`ValidationResult`."""
        return cls(is_valid=True, reason="")

    @classmethod
    def fail(cls, reason: str) -> "ValidationResult":
        """Return a failed :class:`ValidationResult` with ``reason``."""
        return cls(is_valid=False, reason=reason)


# ---------------------------------------------------------------------------
# Rule helpers
# ---------------------------------------------------------------------------

def _require_non_empty(record: Dict[str, Any], field_name: str) -> Optional[str]:
    """Return a failure reason when ``record[field_name]`` is empty."""
    value = record.get(field_name)
    if value is None:
        return f"{field_name} is missing"
    if isinstance(value, str) and not value.strip():
        return f"{field_name} is empty"
    return None


def _require_url(record: Dict[str, Any], field_name: str) -> Optional[str]:
    """Return a failure reason when ``record[field_name]`` is set but malformed."""
    value = record.get(field_name)
    if value is None or value == "":
        return None  # optional
    if not _is_valid_url(value):
        return f"{field_name} is not a valid URL: {value!r}"
    return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def validate_scholarship(record: Dict[str, Any]) -> ValidationResult:
    """Validate a normalised scholarship record.

    Args:
        record: Mapping produced by :func:`backend.parser.normalize.normalize_scholarship`
            (or any dict that satisfies the same shape).

    Returns:
        A :class:`ValidationResult`. ``result.is_valid`` is ``True``
        when every rule passes; otherwise ``result.reason`` explains
        the first failure.
    """
    if not isinstance(record, dict):
        return ValidationResult.fail("record is not a dict")

    checks: tuple[Any, ...] = (
        _require_non_empty(record, "title"),
        _require_non_empty(record, "country"),
        _require_non_empty(record, "source"),
        _require_url(record, "link"),
        _require_url(record, "apply_url"),
    )
    for failure in checks:
        if failure:
            _logger.debug("validate_scholarship FAIL: %s", failure)
            return ValidationResult.fail(failure)
    return ValidationResult.ok()