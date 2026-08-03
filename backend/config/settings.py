"""Runtime settings loader for the ScholarBird backend.

Settings are populated exclusively from environment variables. ``.env``
support is intentionally absent in this foundation phase: a scraper /
Firestore implementation will add ``python-dotenv`` in a later step.

The module exposes a process-wide ``Settings`` object obtained via
``get_settings()``. The function returns the same singleton on repeat
calls so the rest of the codebase can rely on a single source of truth.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from typing import List, Optional, Tuple


def _truthy(raw: Optional[str]) -> bool:
    """Return ``True`` for ``1/true/yes/on`` (case-insensitive)."""
    if raw is None:
        return False
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _csv(raw: Optional[str]) -> Tuple[str, ...]:
    """Split a comma-separated env value into a tuple of stripped tokens.

    Empty tokens are dropped. ``None`` and empty input both return an
    empty tuple. The function never raises so the env loader is robust
    to operator typos.
    """
    if raw is None:
        return ()
    pieces = [token.strip() for token in raw.split(",")]
    return tuple(token for token in pieces if token)


@dataclass(frozen=True)
class Settings:
    """Immutable runtime configuration.

    Attributes:
        env: Current environment label (e.g. ``"development"``).
        log_level: Standard logging level name.
        firebase_credentials_path: Optional path to a service account
            JSON file. Left ``None`` in this phase; the Firebase module
            is intentionally not initialised.
        scraper_user_agent: HTTP user agent used by future scrapers.
        scraper_request_timeout: Default timeout in seconds for HTTP
            requests issued by scrapers.
        enable_parallel: When ``True``, the orchestrator executes
            scrapers concurrently using a :class:`ThreadPoolExecutor`.
            ``False`` keeps execution strictly sequential.
        max_workers: Maximum number of worker threads used when
            ``enable_parallel`` is set. ``1`` degrades to sequential
            behaviour even when the parallel flag is on.
        enabled_scrapers: Optional explicit allow-list. When empty
            every discovered scraper is run; when non-empty only
            names present in the tuple are dispatched.
    """

    env: str
    log_level: str
    firebase_credentials_path: Optional[str]
    scraper_user_agent: str
    scraper_request_timeout: int
    enable_parallel: bool = False
    max_workers: int = 3
    enabled_scrapers: Tuple[str, ...] = field(default_factory=tuple)
    scraper_enabled: bool = False
    scraper_interval_hours: int = 24

    @classmethod
    def from_env(cls) -> "Settings":
        """Build a ``Settings`` instance from the current process env.

        Returns:
            A populated ``Settings`` dataclass.

        Raises:
            ValueError: If ``LOG_LEVEL`` is set to an unsupported value.
        """
        log_level = os.getenv("LOG_LEVEL", "INFO").upper()
        allowed_levels = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        if log_level not in allowed_levels:
            raise ValueError(
                f"Unsupported LOG_LEVEL '{log_level}'. "
                f"Expected one of: {sorted(allowed_levels)}."
            )

        return cls(
            env=os.getenv("APP_ENV", "development"),
            log_level=log_level,
            firebase_credentials_path=os.getenv("FIREBASE_CREDENTIALS_PATH"),
            scraper_user_agent=os.getenv(
                "SCRAPER_USER_AGENT",
                "ScholarBirdBot/1.0 (+https://scholarbird.app)",
            ),
            scraper_request_timeout=_safe_int(
                os.getenv("SCRAPER_REQUEST_TIMEOUT"),
                default=30,
                minimum=1,
            ),
            enable_parallel=_truthy(os.getenv("ENABLE_PARALLEL")),
            max_workers=_safe_int(
                os.getenv("MAX_WORKERS"),
                default=3,
                minimum=1,
            ),
            enabled_scrapers=_csv(os.getenv("ENABLED_SCRAPERS")),
            scraper_enabled=_truthy(os.getenv("SCRAPER_ENABLED")),
            scraper_interval_hours=_safe_int(
                os.getenv("SCRAPER_INTERVAL_HOURS"),
                default=24,
                minimum=1,
            ),
        )


def _safe_int(raw: Optional[str], default: int, minimum: int) -> int:
    """Parse a positive integer env value, falling back to ``default``.

    Args:
        raw: Raw environment string. ``None`` triggers the default.
        default: Fallback value when parsing fails.
        minimum: Lower bound; values below this are clamped to ``minimum``.

    Returns:
        A sanitised integer.
    """
    if raw is None or raw.strip() == "":
        return default
    try:
        parsed = int(raw)
    except ValueError:
        return default
    return max(minimum, parsed)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the cached ``Settings`` singleton.

    Returns:
        The process-wide settings instance.
    """
    return Settings.from_env()


__all__ = ["Settings", "get_settings"]
