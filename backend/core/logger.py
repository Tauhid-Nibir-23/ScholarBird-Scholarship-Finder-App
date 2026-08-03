"""Centralised logging configuration.

The module exposes a single :func:`configure_logging` entry point and
two helpers — :func:`get_logger` for general-purpose modules and
:func:`get_scraper_logger` for code that lives inside the
:mod:`backend.scrapers` package.

Log files
---------
``backend/logs/`` is the output directory and contains three rotating
files by default:

* ``backend.log`` — every record the root logger emits (DEBUG+).
* ``scraper.log`` — every record emitted via ``scrapers.*`` loggers
  (the scraper pipeline gets its own file so it is easy to tail).
* ``errors.log`` — every record at level ERROR or higher from any
  logger. This is the file an on-call engineer should look at first.

Rotation
--------
All file handlers use :class:`logging.handlers.RotatingFileHandler`
with a 5 MB cap and 5 backups (``backend.log.1`` … ``backend.log.5``).
The constants are exposed as module attributes so they can be tweaked
in tests or by environment-aware deployments.

Idempotency
-----------
``configure_logging()`` is safe to call multiple times: the first call
wires the handlers, subsequent calls update the root level only.
"""

from __future__ import annotations

import logging
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

from backend.config.constants import DEFAULT_LOG_LEVEL, LOG_FORMAT

# ---------------------------------------------------------------------------
# Paths and sizes
# ---------------------------------------------------------------------------

_LOGS_DIR: Path = Path(__file__).resolve().parent.parent / "logs"
LOG_FILE_BACKEND: Path = _LOGS_DIR / "backend.log"
LOG_FILE_SCRAPER: Path = _LOGS_DIR / "scraper.log"
LOG_FILE_ERRORS: Path = _LOGS_DIR / "errors.log"

#: Max bytes before a log file is rotated.
LOG_MAX_BYTES: int = 10 * 1024 * 1024  # 10 MB
#: Number of rotated backups to keep on disk.
LOG_BACKUP_COUNT: int = 5

#: Records at this level or higher are duplicated into ``errors.log``.
ERRORS_LOG_LEVEL: int = logging.ERROR

#: Logger namespace whose records are mirrored to ``scraper.log``.
SCRAPER_LOGGER_NAMESPACE: str = "backend.scrapers"

_configured: bool = False


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def configure_logging(
    level: Optional[str] = None,
    *,
    log_file: Optional[Path] = None,
    scraper_log_file: Optional[Path] = None,
    errors_log_file: Optional[Path] = None,
    max_bytes: Optional[int] = None,
    backup_count: Optional[int] = None,
) -> None:
    """Configure root logging for the backend process.

    Subsequent calls are no-ops except for updating the root level, so
    tests and CLI tools may invoke this function freely.

    Args:
        level: Optional level name (e.g. ``"DEBUG"``). Falls back to
            :data:`backend.config.constants.DEFAULT_LOG_LEVEL`.
        log_file: Optional override for the main log file path.
        scraper_log_file: Optional override for the scraper log file path.
        errors_log_file: Optional override for the errors log file path.
        max_bytes: Optional override for the per-file rotation size.
        backup_count: Optional override for the number of rotated backups.
    """
    global _configured

    resolved_level = (level or DEFAULT_LOG_LEVEL).upper()
    resolved_backend_file = Path(log_file) if log_file else LOG_FILE_BACKEND
    resolved_scraper_file = (
        Path(scraper_log_file) if scraper_log_file else LOG_FILE_SCRAPER
    )
    resolved_errors_file = (
        Path(errors_log_file) if errors_log_file else LOG_FILE_ERRORS
    )
    resolved_max_bytes = max_bytes if max_bytes is not None else LOG_MAX_BYTES
    resolved_backup_count = (
        backup_count if backup_count is not None else LOG_BACKUP_COUNT
    )

    # Ensure the logs directory exists before any FileHandler is created.
    for path in (
        resolved_backend_file,
        resolved_scraper_file,
        resolved_errors_file,
    ):
        path.parent.mkdir(parents=True, exist_ok=True)

    root_logger = logging.getLogger()
    root_logger.setLevel(resolved_level)

    formatter = logging.Formatter(LOG_FORMAT)

    if not _configured:
        # Stream (stdout) — always present so operators see live output.
        stream_handler = logging.StreamHandler(stream=sys.stdout)
        stream_handler.setFormatter(formatter)
        root_logger.addHandler(stream_handler)

        # Main rotating file — full-fidelity log of the process.
        backend_handler = _make_rotating_handler(
            resolved_backend_file,
            resolved_max_bytes,
            resolved_backup_count,
            formatter,
        )
        root_logger.addHandler(backend_handler)

        # Errors-only sink — picks up ERROR and CRITICAL records.
        errors_handler = _make_rotating_handler(
            resolved_errors_file,
            resolved_max_bytes,
            resolved_backup_count,
            formatter,
        )
        errors_handler.setLevel(ERRORS_LOG_LEVEL)
        root_logger.addHandler(errors_handler)

        # Tame noisy third-party loggers.
        logging.getLogger("urllib3").setLevel(logging.WARNING)
        logging.getLogger("requests").setLevel(logging.WARNING)
        logging.getLogger("httpx").setLevel(logging.WARNING)
        logging.getLogger("httpcore").setLevel(logging.WARNING)

        _configured = True

    # Attach (or refresh) the scraper-specific file handler. This works
    # on every call so tests can re-point the file mid-process.
    _ensure_scraper_handler(
        resolved_scraper_file,
        resolved_max_bytes,
        resolved_backup_count,
        formatter,
    )


def get_logger(name: str) -> logging.Logger:
    """Return a module-scoped logger.

    Args:
        name: Typically ``__name__`` of the calling module.

    Returns:
        A configured :class:`logging.Logger` instance.
    """
    configure_logging()
    return logging.getLogger(name)


def get_scraper_logger(name: str) -> logging.Logger:
    """Return a logger that routes to ``scraper.log`` in addition to root.

    Args:
        name: Logger name. Should normally start with
            :data:`SCRAPER_LOGGER_NAMESPACE` so the file handler
            filters work as expected.

    Returns:
        A configured :class:`logging.Logger` instance.
    """
    configure_logging()
    return logging.getLogger(name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _make_rotating_handler(
    path: Path,
    max_bytes: int,
    backup_count: int,
    formatter: logging.Formatter,
) -> RotatingFileHandler:
    """Build a :class:`RotatingFileHandler` with our defaults.

    Args:
        path: Destination file path.
        max_bytes: Size cap before rotation.
        backup_count: Number of backups to keep.
        formatter: Formatter to attach.

    Returns:
        A configured rotating handler.
    """
    handler = RotatingFileHandler(
        filename=str(path),
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding="utf-8",
    )
    handler.setFormatter(formatter)
    return handler


_SCRAPER_HANDLER_ATTR = "_scholarbird_scraper_handler"


def _ensure_scraper_handler(
    path: Path,
    max_bytes: int,
    backup_count: int,
    formatter: logging.Formatter,
) -> None:
    """Attach a dedicated file handler to the ``backend.scrapers`` namespace.

    The handler is stored on the namespace logger itself so repeated
    calls do not stack copies. Tests that want a fresh file can call
    :func:`reset_logging` first.

    Args:
        path: Destination file path for scraper records.
        max_bytes: Size cap before rotation.
        backup_count: Number of backups to keep.
        formatter: Formatter to attach.
    """
    namespace_logger = logging.getLogger(SCRAPER_LOGGER_NAMESPACE)
    existing = getattr(namespace_logger, _SCRAPER_HANDLER_ATTR, None)
    if existing is not None:
        existing.close()
        namespace_logger.removeHandler(existing)

    handler = _make_rotating_handler(path, max_bytes, backup_count, formatter)
    handler.setLevel(logging.DEBUG)
    namespace_logger.addHandler(handler)
    namespace_logger.propagate = True
    setattr(namespace_logger, _SCRAPER_HANDLER_ATTR, handler)


def reset_logging() -> None:
    """Tear down all handlers and re-enable configuration.

    Intended for tests only. Production code never needs to call this.
    """
    global _configured
    root_logger = logging.getLogger()
    for handler in list(root_logger.handlers):
        root_logger.removeHandler(handler)

    scraper_logger = logging.getLogger(SCRAPER_LOGGER_NAMESPACE)
    for handler in list(scraper_logger.handlers):
        scraper_logger.removeHandler(handler)
    if hasattr(scraper_logger, _SCRAPER_HANDLER_ATTR):
        delattr(scraper_logger, _SCRAPER_HANDLER_ATTR)

    _configured = False
