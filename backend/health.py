"""Read-only production health reporting for ScholarBird automation."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Optional

from backend.firebase.firebase_config import get_firestore_client
from backend.scrapers.registry import ScraperRegistry


@dataclass(frozen=True)
class HealthReport:
    firebase_connected: bool
    firestore_reachable: bool
    registered_scrapers: tuple[str, ...]
    last_execution: Optional[str]
    last_upload_summary: Optional[dict[str, Any]]
    scheduler_running: bool
    error: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def get_health(scheduler: Optional[Any] = None) -> HealthReport:
    """Return a read-only connectivity and automation status snapshot."""
    firebase_connected = False
    firestore_reachable = False
    error: Optional[str] = None
    try:
        client = get_firestore_client()
        firebase_connected = True
        # A bounded read verifies the live Firestore channel without writing.
        list(client.collection("scholarships").limit(1).stream())
        firestore_reachable = True
    except Exception as exc:  # pragma: no cover - external service boundary
        error = f"{type(exc).__name__}: {exc}"

    registry = ScraperRegistry.discover()
    last_execution = getattr(scheduler, "last_execution", None)
    return HealthReport(
        firebase_connected=firebase_connected,
        firestore_reachable=firestore_reachable,
        registered_scrapers=tuple(registry.names()),
        last_execution=(last_execution.isoformat() if last_execution else None),
        last_upload_summary=getattr(scheduler, "last_upload_summary", None),
        scheduler_running=bool(getattr(scheduler, "running", False)),
        error=error,
    )
