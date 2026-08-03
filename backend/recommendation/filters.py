"""Hard filters performed before the scoring loop."""

from __future__ import annotations

from datetime import date, datetime
from functools import lru_cache
from typing import Any, Optional

from .matcher import matches, scholarship_value
from .models import UserProfile


def deadline_date(value: Any) -> Optional[date]:
    return _deadline_date(str(value or "").strip())


@lru_cache(maxsize=4096)
def _deadline_date(text: str) -> Optional[date]:
    if not text or text.casefold() in {"rolling", "ongoing", "varies", "unknown"}:
        return None
    for pattern in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%B %d, %Y", "%d %B %Y"):
        try: return datetime.strptime(text, pattern).date()
        except ValueError: pass
    try: return datetime.fromisoformat(text.replace("Z", "+00:00")).date()
    except ValueError: return None


def reject_reason(record: dict[str, Any], profile: UserProfile, *, today: Optional[date] = None) -> Optional[str]:
    """Return the first mandatory mismatch, otherwise ``None``."""
    if record.get("isHidden") is True or record.get("active") is False or record.get("isActive") is False:
        return "Scholarship is inactive"
    if profile.preferred_degree and not matches(profile.preferred_degree, record.get("degree")):
        return "Degree does not match"
    if profile.restrict_country and profile.preferred_country and not matches(profile.preferred_country, record.get("country")):
        return "Country does not match"
    required_cgpa = scholarship_value(record, "min_cgpa", "minCgpa")
    if required_cgpa not in (None, "") and profile.cgpa is not None and profile.cgpa < float(required_cgpa):
        return "CGPA below minimum"
    required_ielts = scholarship_value(record, "min_ielts", "minIelts", "ieltsScore")
    if required_ielts not in (None, "") and profile.ielts is not None and profile.ielts < float(required_ielts):
        return "IELTS below minimum"
    deadline = deadline_date(record.get("deadline"))
    if deadline and deadline < (today or date.today()):
        return "Deadline has passed"
    return None
