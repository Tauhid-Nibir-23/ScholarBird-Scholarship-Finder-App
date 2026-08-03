"""Generic retry decorator with exponential backoff.

The decorator is intentionally pure: it accepts a callable and retries
it according to a :class:`RetryPolicy`. It does not import any I/O
library so it can wrap scraping, HTTP, and Firestore calls uniformly.
"""

from __future__ import annotations

import functools
import random
import time
from dataclasses import dataclass
from typing import Callable, Iterable, Optional, Tuple, Type, TypeVar

from backend.core.exceptions import ScholarBirdError
from backend.core.logger import get_logger

T = TypeVar("T")
_logger = get_logger(__name__)


@dataclass(frozen=True)
class RetryPolicy:
    """Configuration for :func:`retry`.

    Attributes:
        max_attempts: Total attempts including the first try. Must be
            ``>= 1``.
        base_delay: Initial delay in seconds before retrying.
        max_delay: Upper bound for the computed backoff delay.
        jitter: If ``True``, applies uniform jitter between ``0`` and
            the computed delay.
        retry_on: Tuple of exception types that should trigger a retry.
            ``ScholarBirdError`` is always retried on.
    """

    max_attempts: int = 3
    base_delay: float = 1.0
    max_delay: float = 30.0
    jitter: bool = True
    retry_on: Tuple[Type[BaseException], ...] = ()

    def __post_init__(self) -> None:
        if self.max_attempts < 1:
            raise ValueError("max_attempts must be >= 1")
        if self.base_delay < 0:
            raise ValueError("base_delay must be >= 0")
        if self.max_delay < self.base_delay:
            raise ValueError("max_delay must be >= base_delay")


class RetryExhausted(ScholarBirdError):
    """Raised when a retried callable exhausts its attempt budget."""

    def __init__(self, attempts: int, last_exception: BaseException) -> None:
        super().__init__(
            f"Retry exhausted after {attempts} attempts: "
            f"{type(last_exception).__name__}: {last_exception}"
        )
        self.attempts = attempts
        self.last_exception = last_exception


def _compute_delay(policy: RetryPolicy, attempt: int) -> float:
    """Compute the sleep duration for ``attempt`` (zero-based)."""
    delay = min(policy.base_delay * (2 ** attempt), policy.max_delay)
    if policy.jitter:
        delay = random.uniform(0, delay)
    return delay


def retry(
    policy: Optional[RetryPolicy] = None,
    *,
    retry_on: Optional[Iterable[Type[BaseException]]] = None,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """Decorate ``func`` with a retry loop.

    Args:
        policy: Optional :class:`RetryPolicy`. A default is used when
            omitted.
        retry_on: Optional iterable of additional exception types that
            should trigger a retry. The base
            :class:`backend.core.exceptions.ScholarBirdError` is always
            retried on.

    Returns:
        A decorator that wraps the target callable.
    """
    resolved = policy or RetryPolicy()
    extra_exceptions: Tuple[Type[BaseException], ...] = tuple(retry_on or ())
    retryable = (ScholarBirdError, *resolved.retry_on, *extra_exceptions)

    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        def wrapper(*args: object, **kwargs: object) -> T:
            last_error: Optional[BaseException] = None
            for attempt in range(resolved.max_attempts):
                try:
                    return func(*args, **kwargs)
                except retryable as exc:  # type: ignore[misc]
                    last_error = exc
                    if attempt + 1 >= resolved.max_attempts:
                        break
                    delay = _compute_delay(resolved, attempt)
                    _logger.warning(
                        "Retrying %s after error (attempt %d/%d) in %.2fs: %s",
                        getattr(func, "__qualname__", repr(func)),
                        attempt + 1,
                        resolved.max_attempts,
                        delay,
                        exc,
                    )
                    time.sleep(delay)
            assert last_error is not None  # for type checkers
            raise RetryExhausted(resolved.max_attempts, last_error) from last_error

        return wrapper

    return decorator