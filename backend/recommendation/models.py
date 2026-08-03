"""Public, schema-neutral input and output models for recommendations."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping, Optional


def _text(value: Any) -> Optional[str]:
    value = str(value).strip() if value is not None else ""
    return value or None


def _number(value: Any) -> Optional[float]:
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


@dataclass(frozen=True)
class UserProfile:
    preferred_country: Optional[str] = None
    preferred_degree: Optional[str] = None
    preferred_field: Optional[str] = None
    cgpa: Optional[float] = None
    cgpa_scale: float = 4.0
    ielts: Optional[float] = None
    english_medium: Optional[bool] = None
    research_interest: Optional[bool] = None
    funding_preference: tuple[str, ...] = ()
    preferred_intake: tuple[str, ...] = ()
    restrict_country: bool = False

    @classmethod
    def from_mapping(cls, data: Mapping[str, Any]) -> "UserProfile":
        """Read established Firestore profile names plus snake-case aliases."""
        def values(*keys: str) -> tuple[str, ...]:
            raw = next((data[k] for k in keys if data.get(k) is not None), [])
            if isinstance(raw, (list, tuple, set)):
                return tuple(str(item).strip() for item in raw if str(item).strip())
            return (str(raw).strip(),) if str(raw).strip() else ()
        return cls(
            preferred_country=_text(data.get("preferredCountry", data.get("preferred_country"))),
            preferred_degree=_text(data.get("preferredDegree", data.get("preferred_degree"))),
            preferred_field=_text(data.get("preferredField", data.get("preferred_field"))),
            cgpa=_number(data.get("cgpa")), cgpa_scale=_number(data.get("cgpaScale", data.get("cgpa_scale"))) or 4.0,
            ielts=_number(data.get("ielts")), english_medium=data.get("englishMedium", data.get("english_medium")),
            research_interest=data.get("researchInterest", data.get("researchExperience", data.get("research_interest"))),
            funding_preference=values("fundingTypes", "fundingPreference", "funding_preference"),
            preferred_intake=values("intakes", "preferredIntake", "preferred_intake"),
            restrict_country=bool(data.get("restrictCountry", data.get("restrict_country", False))),
        )


@dataclass(frozen=True)
class Recommendation:
    scholarship_id: str
    match_score: int
    reasons: tuple[str, ...] = ()
    matched_fields: tuple[str, ...] = ()
    missing_requirements: tuple[str, ...] = ()
    warnings: tuple[str, ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {"scholarshipId": self.scholarship_id, "matchScore": self.match_score, "reasons": list(self.reasons), "matchedFields": list(self.matched_fields), "missingRequirements": list(self.missing_requirements), "warnings": list(self.warnings)}
