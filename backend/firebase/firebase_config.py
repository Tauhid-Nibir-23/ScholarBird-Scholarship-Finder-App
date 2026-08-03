"""Firebase Admin SDK initialisation.

The module exposes a single entry point — :func:`get_firebase_app` —
which lazily initialises the Firebase Admin SDK exactly once per
process. Subsequent calls return the cached instance so callers never
have to think about lifecycle management.

Credentials
-----------
The service-account JSON path is read from the ``FIREBASE_CREDENTIALS_PATH``
environment variable. A ``.env`` file at the project root is loaded the
first time :func:`get_firebase_app` is invoked so the same value can
live in version-controlled configuration without leaking secrets into
the shell. **Never hard-code credentials inside source files.**

A project-level database id can be supplied via
``FIRESTORE_DATABASE_ID``; the default ``"(default)"`` works for the
live Firebase project.

Errors
------
* :class:`ConfigurationError` — credentials path is missing, the file
  does not exist, or the file is unreadable.
* :class:`FirebaseError` — the Admin SDK itself fails to initialise
  (corrupt credentials, network problem during key validation, etc.).
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional

from backend.config.settings import get_settings
from backend.core.exceptions import ConfigurationError, FirebaseError
from backend.core.logger import get_logger

_logger = get_logger(__name__)

#: Module-level cache for the singleton Firebase app.
_app_instance: Optional[Any] = None
#: Module-level cache for the singleton Firestore client.
_client_instance: Optional[Any] = None
#: Tracks whether the lazy loader has attempted to read the .env file.
_env_loaded: bool = False


# ---------------------------------------------------------------------------
# .env loader — invoked exactly once per process
# ---------------------------------------------------------------------------

def _project_root() -> Path:
    """Return the project root that holds the ``.env`` file."""
    return Path(__file__).resolve().parent.parent.parent


def _load_dotenv_once() -> None:
    """Load ``.env`` from the project root if it exists.

    The function is idempotent and silent: missing files are fine
    because the credentials may also come from the process
    environment. Errors reading the file are logged and swallowed so
    a malformed ``.env`` cannot crash the pipeline.
    """
    global _env_loaded
    if _env_loaded:
        return
    _env_loaded = True

    env_path = _project_root() / ".env"
    if not env_path.exists():
        _logger.debug("No .env file at %s — using process env only", env_path)
        return

    try:
        # ``python-dotenv`` is the Phase-4 dependency announced in
        # ``backend/requirements.txt``. It is imported lazily so the
        # rest of the backend does not fail when the SDK is absent.
        from dotenv import load_dotenv

        load_dotenv(env_path, override=False)
        _logger.info("Loaded environment variables from %s", env_path)
    except Exception as exc:  # pragma: no cover - defensive logging
        _logger.warning("Failed to load .env at %s: %s", env_path, exc)


# ---------------------------------------------------------------------------
# Credential resolution
# ---------------------------------------------------------------------------

def _resolve_credentials_path() -> str:
    """Return the absolute service-account JSON path.

    Returns:
        Path string suitable for :func:`firebase_admin.credentials.Certificate`.

    Raises:
        ConfigurationError: When no path is configured or the file
            does not exist.
    """
    _load_dotenv_once()

    raw = os.getenv("FIREBASE_CREDENTIALS_PATH")
    if raw is None or not raw.strip():
        # Fall back to the cached settings object (which reads the
        # same env var). Kept as a fallback in case ``get_settings``
        # was monkey-patched in tests.
        settings = get_settings()
        raw = settings.firebase_credentials_path

    if raw is None or not str(raw).strip():
        raise ConfigurationError(
            "FIREBASE_CREDENTIALS_PATH is not set. Configure the path "
            "to your Firebase service-account JSON via environment "
            "variable or .env before running the uploader."
        )

    path = Path(raw).expanduser()
    if not path.is_file():
        raise ConfigurationError(
            f"Firebase credentials not found at {path}. "
            "Verify FIREBASE_CREDENTIALS_PATH points to an existing "
            "service-account JSON file."
        )
    return str(path)


def _resolve_database_id() -> str:
    """Return the Firestore database id from env, defaulting to ``"(default)"``."""
    _load_dotenv_once()
    return os.getenv("FIRESTORE_DATABASE_ID") or "(default)"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_firebase_app() -> Any:
    """Return the lazily-initialised Firebase Admin app singleton.

    The first call initialises the SDK using
    :func:`firebase_admin.initialize_app` with the service-account
    JSON path read from the environment. Subsequent calls return the
    cached app instance — reinitialisation would raise ``ValueError``
    from the SDK itself, so the cache is the only safe pattern.

    Returns:
        The :class:`firebase_admin.App` instance.

    Raises:
        ConfigurationError: When credentials are missing or invalid.
        FirebaseError: When :func:`firebase_admin.initialize_app`
            itself fails for any other reason.
    """
    global _app_instance

    if _app_instance is not None:
        return _app_instance

    try:
        import firebase_admin
        from firebase_admin import credentials
    except ImportError as exc:  # pragma: no cover - defensive
        raise FirebaseError(
            "firebase_admin is not installed. Install it before "
            "calling get_firebase_app()."
        ) from exc

    # Guard against double-initialisation when this function is
    # called from multiple threads during a test fan-out.
    try:
        existing = firebase_admin.get_app()
    except ValueError:
        existing = None

    if existing is not None:
        _app_instance = existing
        return _app_instance

    creds_path = _resolve_credentials_path()
    db_id = _resolve_database_id()

    try:
        credential = credentials.Certificate(creds_path)
        _app_instance = firebase_admin.initialize_app(
            credential,
            {"databaseURL": None},
        )
        _logger.info(
            "Firebase Admin initialised (credentials=%s, database=%s)",
            creds_path,
            db_id,
        )
        return _app_instance
    except ConfigurationError:
        raise
    except Exception as exc:  # pragma: no cover - defensive
        raise FirebaseError(
            f"Firebase Admin SDK initialisation failed: {exc}"
        ) from exc


def get_firestore_client() -> Any:
    """Return a Firestore client bound to the singleton Firebase app.

    The client is cached alongside the app so the pipeline only opens
    one network channel per process.

    Returns:
        A :class:`google.cloud.firestore.Client` instance.
    """
    global _client_instance

    if _client_instance is not None:
        return _client_instance

    app = get_firebase_app()

    try:
        from firebase_admin import firestore
    except ImportError as exc:  # pragma: no cover - defensive
        raise FirebaseError(
            "google-cloud-firestore is not installed. Install it "
            "before calling get_firestore_client()."
        ) from exc

    _client_instance = firestore.client(
        app=app,
        database_id=_resolve_database_id(),
    )
    _logger.info("Firestore client ready (database=%s)",
                 _resolve_database_id())
    return _client_instance


def reset_firebase_state() -> None:
    """Clear module-level singletons (testing helper).

    Production code never needs to call this. Tests that monkey-patch
    the credentials path between cases use it to force a fresh
    initialisation on the next call.
    """
    global _app_instance, _client_instance, _env_loaded
    _app_instance = None
    _client_instance = None
    _env_loaded = False


__all__ = [
    "get_firebase_app",
    "get_firestore_client",
    "reset_firebase_state",
]
