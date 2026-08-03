"""Abstract base class for all scrapers — the **Generic Scraper Engine**.

Every concrete scraper in :mod:`backend.scrapers` inherits from
:class:`BaseScraper` and inherits, for free:

* a managed :class:`httpx.Client` lifecycle (``with`` block friendly),
* a default retry policy built on :func:`backend.core.retry.retry`,
* polite request throttling (:meth:`BaseScraper.sleep`),
* header construction (:meth:`BaseScraper.build_headers`),
* :meth:`BaseScraper.request` — a single-URL HTTP wrapper that already
  converts transport failures into :class:`NetworkException` and
  non-2xx responses into :class:`RobotsDeniedException` when the
  status signals a policy block,
* logging helpers (:meth:`log_success`, :meth:`log_error`),
* a generic :meth:`safe_get` for nested dict lookups,
* context-manager support (``__enter__`` / ``__exit__``).

Subclasses are still responsible for two things:

1. :meth:`fetch` — how to retrieve the raw payload they need (a single
   page, several JSON files, etc.). The base class exposes
   :meth:`request` for the simple "one URL" case but lets scrapers
   override :meth:`fetch` entirely when they need to.
2. :meth:`parse` — how to convert that payload into
   :class:`backend.models.Scholarship` records.

The convenience :meth:`run` chains both, so the contract for callers
remains ``scraper.run() -> List[Scholarship]``.
"""

from __future__ import annotations

import random
import time
from abc import ABC, abstractmethod
from typing import Any, Iterable, List, Mapping, Optional

import httpx

from backend.config.settings import Settings, get_settings
from backend.core.exceptions import (
    NetworkException,
    RobotsDeniedException,
)
from backend.core.helpers import safe_get as _safe_get
from backend.core.logger import get_logger, get_scraper_logger
from backend.core.retry import RetryPolicy, retry
from backend.models.scholarship import Scholarship

# Module-level logger — every scraper inherits a child of this namespace.
_logger = get_scraper_logger(__name__)


# Status codes that conventionally signal a robots/policy block rather
# than a transient transport problem.
_ROBOTS_DENIED_STATUS_CODES: frozenset[int] = frozenset({401, 403, 451})


class BaseScraper(ABC):
    """Reusable foundation for every ScholarBird scraper.

    Subclasses MUST:

    * Set :attr:`name` to a short lowercase identifier.
    * Implement :meth:`fetch` (and optionally :meth:`parse`).

    Subclasses MAY override :attr:`retry_policy`,
    :attr:`min_request_delay`, :attr:`max_request_delay`,
    :meth:`build_headers`, or :meth:`request` to customise the
    behaviour for their particular upstream source.
    """

    # ------------------------------------------------------------------
    # Class-level configuration
    # ------------------------------------------------------------------

    #: Short human-readable name used in logs and the ``source`` field.
    name: str = "base"

    #: Default retry policy applied to :meth:`request`. Override in
    #: subclasses that hit flaky endpoints.
    retry_policy: RetryPolicy = RetryPolicy(
        max_attempts=3,
        base_delay=1.0,
        max_delay=8.0,
        jitter=True,
    )

    #: Lower bound (seconds) for the polite-delay window.
    min_request_delay: float = 1.0
    #: Upper bound (seconds) for the polite-delay window.
    max_request_delay: float = 2.0

    # ------------------------------------------------------------------
    # Construction & lifecycle
    # ------------------------------------------------------------------

    def __init__(
        self,
        source_url: str,
        *,
        settings: Optional[Settings] = None,
        client: Optional[httpx.Client] = None,
    ) -> None:
        """Initialise the scraper.

        Args:
            source_url: Upstream URL the scraper reads from. Required.
            settings: Optional pre-built :class:`Settings` instance.
                Falls back to :func:`get_settings` for the singleton.
            client: Optional pre-configured :class:`httpx.Client`. When
                omitted the base class builds one on demand via
                :meth:`_ensure_client`. When passed in, the caller owns
                the client's lifecycle (the scraper will not close it
                in ``__exit__``).
        """
        self.source_url: str = source_url
        self._settings: Settings = settings or get_settings()
        self._external_client: bool = client is not None
        self._client: Optional[httpx.Client] = client
        self._closed: bool = False
        _logger.debug(
            "Scraper %s initialised for %s (timeout=%ss, ua=%s)",
            self.name,
            source_url,
            self._settings.scraper_request_timeout,
            self._settings.scraper_user_agent,
        )

    # ------------------------------------------------------------------
    # Context manager — auto-closes the owned httpx.Client
    # ------------------------------------------------------------------

    def __enter__(self) -> "BaseScraper":
        self._ensure_client()
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.close()

    def close(self) -> None:
        """Release the owned :class:`httpx.Client` if one was created."""
        if self._client is not None and not self._external_client:
            try:
                self._client.close()
            finally:
                self._client = None
                self._closed = True

    # ------------------------------------------------------------------
    # Logging helpers
    # ------------------------------------------------------------------

    @property
    def logger(self) -> Any:
        """Logger scoped to ``backend.scrapers.<class>``.

        Subclasses can use ``self.logger.info(...)`` instead of building
        their own logger.
        """
        return _logger

    def log_success(self, message: str, *args: Any) -> None:
        """Emit a level-INFO success log line.

        Args:
            message: ``logging``-style format string.
            *args: Positional arguments for the format string.
        """
        self.logger.info(message, *args)

    def log_error(
        self,
        message: str,
        exc: Optional[BaseException] = None,
        *args: Any,
    ) -> None:
        """Emit a level-ERROR log line, optionally with an exception.

        Args:
            message: ``logging``-style format string.
            exc: Optional exception to attach. When provided, the
                exception is logged via ``logger.exception`` style
                stack-trace dump.
            *args: Positional arguments for the format string.
        """
        if exc is not None:
            self.logger.error("%s: %s", message, exc, *args, exc_info=exc)
        else:
            self.logger.error(message, *args)

    # ------------------------------------------------------------------
    # Generic dict helper — thin pass-through to core.helpers
    # ------------------------------------------------------------------

    @staticmethod
    def safe_get(
        mapping: Optional[Mapping[str, Any]],
        *keys: str,
        default: Any = None,
    ) -> Any:
        """Look up nested keys in ``mapping`` without raising ``KeyError``.

        Thin re-export of :func:`backend.core.helpers.safe_get` so
        scrapers can call ``self.safe_get(...)`` without importing
        from :mod:`backend.core.helpers` directly.

        Args:
            mapping: Optional source mapping. ``None`` returns ``default``.
            keys: Sequence of keys forming a nested path.
            default: Value returned when any segment is missing.

        Returns:
            The looked-up value or ``default``.
        """
        return _safe_get(mapping, *keys, default=default)

    # ------------------------------------------------------------------
    # Throttling
    # ------------------------------------------------------------------

    def sleep(self, seconds: Optional[float] = None) -> None:
        """Sleep for a polite delay between successive HTTP calls.

        Args:
            seconds: Optional explicit delay in seconds. When omitted,
                a uniform random value in
                ``[min_request_delay, max_request_delay]`` is used.
        """
        if seconds is None:
            delay = random.uniform(self.min_request_delay, self.max_request_delay)
        else:
            delay = max(0.0, float(seconds))
        self.logger.debug("Throttling %.2fs before next request", delay)
        time.sleep(delay)

    # ------------------------------------------------------------------
    # HTTP plumbing
    # ------------------------------------------------------------------

    def build_headers(self) -> dict[str, str]:
        """Return the default HTTP headers for upstream calls.

        Override in subclasses to add cookies, CSRF tokens, or
        site-specific ``Accept`` headers.

        Returns:
            A copy of the headers dict — callers may mutate it freely.
        """
        return {
            "User-Agent": self._settings.scraper_user_agent,
            "Accept": (
                "application/javascript, text/javascript, "
                "application/json, text/html;q=0.9, */*; q=0.5"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        }

    def _ensure_client(self) -> httpx.Client:
        """Return a live :class:`httpx.Client`, creating one on demand."""
        if self._client is None:
            self._client = httpx.Client(
                headers=self.build_headers(),
                timeout=float(self._settings.scraper_request_timeout),
                follow_redirects=True,
            )
        return self._client

    @property
    def client(self) -> httpx.Client:
        """Live :class:`httpx.Client` — creates one on first access."""
        return self._ensure_client()

    @retry(retry_on=(NetworkException, httpx.HTTPError))
    def request(
        self,
        url: str,
        *,
        params: Optional[Mapping[str, Any]] = None,
        headers: Optional[Mapping[str, str]] = None,
        timeout: Optional[float] = None,
    ) -> httpx.Response:
        """Perform a single GET with retry, throttling, and typed errors.

        Args:
            url: Absolute URL to fetch.
            params: Optional query-string parameters.
            headers: Optional extra headers (merged on top of
                :meth:`build_headers`).
            timeout: Optional override for the request timeout. When
                omitted, :attr:`Settings.scraper_request_timeout` is
                used.

        Returns:
            The :class:`httpx.Response` when the status code is 2xx.

        Raises:
            NetworkException: For transport failures (DNS, connection
                refused, TLS errors, timeouts, 5xx responses).
            RobotsDeniedException: When the upstream returns a status
                that signals an access block (``401`` / ``403`` /
                ``451``).
        """
        merged_headers: dict[str, str] = dict(self.build_headers())
        if headers:
            merged_headers.update(headers)

        effective_timeout = float(
            timeout if timeout is not None else self._settings.scraper_request_timeout
        )
        client = self._ensure_client()
        try:
            response = client.get(
                url,
                params=dict(params) if params else None,
                headers=merged_headers,
                timeout=effective_timeout,
            )
        except httpx.HTTPError as exc:
            raise NetworkException(
                f"{self.name}: HTTP error fetching {url}: {exc}",
                url=url,
            ) from exc

        if response.status_code in _ROBOTS_DENIED_STATUS_CODES:
            raise RobotsDeniedException(
                f"{self.name}: access denied to {url} "
                f"(HTTP {response.status_code})",
                url=url,
            )

        if response.status_code >= 400:
            raise NetworkException(
                f"{self.name}: upstream error for {url}: "
                f"HTTP {response.status_code}",
                url=url,
                status_code=response.status_code,
            )

        self.logger.debug(
            "Fetched %s -> %d bytes (HTTP %d)",
            url,
            len(response.content),
            response.status_code,
        )
        return response

    # ------------------------------------------------------------------
    # Abstract contract — implemented by subclasses
    # ------------------------------------------------------------------

    @abstractmethod
    def fetch(self) -> str:
        """Retrieve raw page content from the upstream source.

        Returns:
            Raw payload (typically a JSON or HTML string).

        Raises:
            backend.core.exceptions.NetworkException: When a network
                call fails after retries are exhausted.
            backend.core.exceptions.RobotsDeniedException: When the
                upstream denies access.
        """

    @abstractmethod
    def parse(self, raw_content: str) -> List[Scholarship]:
        """Parse ``raw_content`` into typed :class:`Scholarship` records.

        Args:
            raw_content: Output of :meth:`fetch`.

        Returns:
            A list of parsed scholarships (possibly empty).

        Raises:
            backend.core.exceptions.ParsingException: When the payload
                cannot be decoded into the model.
        """

    # ------------------------------------------------------------------
    # Pipeline
    # ------------------------------------------------------------------

    def run(self) -> List[Scholarship]:
        """Execute the full ``fetch`` → ``parse`` pipeline.

        Returns:
            Parsed scholarships.
        """
        raw = self.fetch()
        return self.parse(raw)

    # ------------------------------------------------------------------
    # Dunder helpers
    # ------------------------------------------------------------------

    def __repr__(self) -> str:  # pragma: no cover - trivial
        return (
            f"{type(self).__name__}(name={self.name!r}, "
            f"url={self.source_url!r})"
        )


__all__ = ["BaseScraper", "Iterable"]