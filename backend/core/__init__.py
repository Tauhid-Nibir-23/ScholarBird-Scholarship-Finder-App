"""Core infrastructure utilities shared across the backend.

Modules in this package provide cross-cutting concerns (logging,
retries, exception hierarchy, helpers) and must not import any
project-specific business logic.
"""

from backend.core.exceptions import (
    ScholarBirdError,
    ConfigurationError,
    ScraperException,
    NetworkException,
    RobotsDeniedException,
    ParsingException,
    ValidationError,
    DuplicateError,
    FirebaseError,
    # Backward-compatible aliases
    ScraperError,
    ParseError,
)
from backend.core.logger import (
    configure_logging,
    get_logger,
    get_scraper_logger,
)
from backend.core.retry import retry, RetryPolicy, RetryExhausted
from backend.core.helpers import (
    chunked,
    safe_get,
    coalesce,
    truncate,
    slugify,
)

__all__ = [
    # exceptions — new hierarchy
    "ScholarBirdError",
    "ConfigurationError",
    "ScraperException",
    "NetworkException",
    "RobotsDeniedException",
    "ParsingException",
    "ValidationError",
    "DuplicateError",
    "FirebaseError",
    # exceptions — legacy aliases
    "ScraperError",
    "ParseError",
    # logger
    "configure_logging",
    "get_logger",
    "get_scraper_logger",
    # retry
    "retry",
    "RetryPolicy",
    "RetryExhausted",
    # helpers
    "chunked",
    "safe_get",
    "coalesce",
    "truncate",
    "slugify",
]