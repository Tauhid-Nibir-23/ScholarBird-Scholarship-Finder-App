"""Deterministic scholarship lifecycle and change-history evaluation."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Mapping

from backend.recommendation.filters import deadline_date

_TRACKED = ("title", "description", "deadline", "funding", "eligibility", "degree", "field", "country", "university", "image", "apply_url", "tags", "status")


def _timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _status(record: Mapping[str, Any], today: date) -> str:
    deadline = deadline_date(record.get("deadline"))
    return "expired" if deadline and deadline < today else "active"


def _deadline_days(record: Mapping[str, Any], today: date) -> int | None:
    deadline = deadline_date(record.get("deadline"))
    return (deadline - today).days if deadline else None


def initial_lifecycle_metadata(record: Mapping[str, Any], *, today: date | None = None) -> dict[str, Any]:
    """Return lifecycle metadata for a new document without mutating it."""
    current_day = today or date.today()
    now = _timestamp()
    return {"status": _status(record, current_day), "last_checked_at": now, "last_changed_at": now, "change_count": 0, "changed_fields": [], "is_updated": False, "is_expired": _status(record, current_day) == "expired", "days_until_deadline": _deadline_days(record, current_day), "change_history": []}


def evaluate_lifecycle(existing: Mapping[str, Any], candidate: Mapping[str, Any], *, today: date | None = None) -> dict[str, Any]:
    """Return only changed content plus metadata; immutable fields never appear."""
    current_day = today or date.today()
    updates: dict[str, Any] = {}
    changed_fields: list[str] = []
    for field in _TRACKED:
        if field == "status" or field not in candidate:
            continue
        if existing.get(field) != candidate[field]:
            updates[field] = candidate[field]; changed_fields.append(field)
    desired_status = _status(candidate, current_day)
    if existing.get("status") != desired_status:
        updates["status"] = desired_status
        if "status" not in changed_fields: changed_fields.append("status")
    desired_expired = desired_status == "expired"
    desired_days = _deadline_days(candidate, current_day)
    if not changed_fields:
        return {}
    now = _timestamp()
    history = list(existing.get("change_history") or [])[-9:]
    history.append({"timestamp": now, "changed_fields": list(changed_fields), "source": candidate.get("source") or existing.get("source") or "unknown"})
    updates.update({"last_checked_at": now, "last_changed_at": now, "change_count": int(existing.get("change_count") or 0) + 1, "changed_fields": changed_fields, "is_updated": True, "is_expired": desired_expired, "days_until_deadline": desired_days, "change_history": history})
    return updates


def unavailable_update(existing: Mapping[str, Any], *, source: str, today: date | None = None) -> dict[str, Any]:
    """Mark a record unavailable when an authoritative source snapshot omits it."""
    if existing.get("status") == "unavailable": return {}
    current_day = today or date.today(); now = _timestamp()
    history = list(existing.get("change_history") or [])[-9:]
    history.append({"timestamp": now, "changed_fields": ["status"], "source": source})
    return {"status": "unavailable", "last_checked_at": now, "last_changed_at": now, "change_count": int(existing.get("change_count") or 0) + 1, "changed_fields": ["status"], "is_updated": True, "is_expired": _status(existing, current_day) == "expired", "days_until_deadline": _deadline_days(existing, current_day), "change_history": history}


def reconcile_unavailable(existing_records: list[Mapping[str, Any]], current_official_ids: set[str], *, source: str, today: date | None = None) -> list[tuple[Mapping[str, Any], dict[str, Any]]]:
    """Return partial unavailable updates for records absent from an official snapshot."""
    updates: list[tuple[Mapping[str, Any], dict[str, Any]]] = []
    for existing in existing_records:
        official_id = str(existing.get("official_id") or existing.get("officialId") or "")
        if existing.get("source") == source and official_id and official_id not in current_official_ids:
            update = unavailable_update(existing, source=source, today=today)
            if update: updates.append((existing, update))
    return updates
