"""Exception hierarchy for the ScholarBird backend.

All custom exceptions inherit from :class:`ScholarBirdError` so callers
can catch a single base type while still having access to specific
subclasses when finer handling is required.

Layered categories
------------------
* :class:`ScholarBirdError` — base class for every error in the project.
* :class:`ConfigurationError` — invalid / missing runtime settings.
* :class:`ScraperException` — base class for anything a scraper may raise
  while fetching or parsing upstream sources.
* :class:`NetworkException` — transport-layer failure (DNS, connection,
  timeout, non-2xx response). Typically retryable.
* :class:`RobotsDeniedException` — upstream ``robots.txt`` forbids the
  requested resource. Not retryable.
* :class:`ParsingException` — content was retrieved successfully but
  could not be converted to a typed model.
* :class:`ValidationError` — a parsed record fails schema validation.
* :class:`DuplicateError` — a record is identified as a duplicate.
* :class:`FirebaseError` — Firebase / Firestore interaction failed.

Backward compatibility
----------------------
Earlier phases exported the shorter names ``ScraperError`` and
``ParseError``. They are preserved here as direct aliases for the new
:class:`ScraperException` and :class:`ParsingException` so existing
imports keep compiling.
"""

from __future__ import annotations


class ScholarBirdError(Exception):
    """Base class for every error raised by the ScholarBird backend."""


class ConfigurationError(ScholarBirdError):
    """Raised when the runtime configuration is missing or invalid."""


# ---------------------------------------------------------------------------
# Scraper exceptions
# ---------------------------------------------------------------------------


class ScraperException(ScholarBirdError):
    """Base class for any failure inside a :class:`BaseScraper`.

    Subclasses cover the three main failure modes a scraper can hit:
    network problems (:class:`NetworkException`), access denied by
    ``robots.txt`` (:class:`RobotsDeniedException`), and decoding
    failures (:class:`ParsingException`).
    """


class NetworkException(ScraperException):
    """Raised when a network call to an upstream source fails.

    Includes connection errors, timeouts, TLS errors, and non-2xx HTTP
    responses. Most instances are transient and therefore retryable.
    """

    def __init__(
        self,
        message: str,
        *,
        url: str | None = None,
        status_code: int | None = None,
    ) -> None:
        super().__init__(message)
        self.url: str | None = url
        self.status_code: int | None = status_code


class RobotsDeniedException(ScraperException):
    """Raised when the upstream ``robots.txt`` forbids the target URL.

    Distinct from :class:`NetworkException` so callers can tell apart
    "site is unreachable" from "site is reachable but rules say no".
    These errors are **not** retryable.
    """

    def __init__(self, message: str, *, url: str | None = None) -> None:
        super().__init__(message)
        self.url: str | None = url


class ParsingException(ScraperException):
    """Raised when raw content cannot be converted to a typed model."""

    def __init__(self, message: str, *, source: str | None = None) -> None:
        super().__init__(message)
        self.source: str | None = source


# ---------------------------------------------------------------------------
# Other domain exceptions
# ---------------------------------------------------------------------------


class ValidationError(ScholarBirdError):
    """Raised when a parsed record fails validation rules."""


class DuplicateError(ScholarBirdError):
    """Raised when a record is identified as a duplicate of an existing one."""


class FirebaseError(ScholarBirdError):
    """Raised when a Firebase interaction fails."""


# ---------------------------------------------------------------------------
# Backward-compatible aliases
# ---------------------------------------------------------------------------

#: Alias kept for code written before the Generic Scraper Engine refactor.
ScraperError = ScraperException
#: Alias kept for code written before the Generic Scraper Engine refactor.
ParseError = ParsingException


__all__ = [
    # Base
    "ScholarBirdError",
    "ConfigurationError",
    # Scraper hierarchy
    "ScraperException",
    "NetworkException",
    "RobotsDeniedException",
    "ParsingException",
    # Other domain
    "ValidationError",
    "DuplicateError",
    "FirebaseError",
    # Legacy aliases
    "ScraperError",
    "ParseError",
]