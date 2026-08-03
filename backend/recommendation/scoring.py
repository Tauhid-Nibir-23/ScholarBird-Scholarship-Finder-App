"""Explainable 0-100 scoring for already-filtered scholarships."""

from __future__ import annotations

from typing import Any

from .matcher import matches, scholarship_value
from .models import Recommendation, UserProfile
from .weights import RecommendationWeights


def score(record: dict[str, Any], profile: UserProfile, weights: RecommendationWeights) -> Recommendation:
    points = 0.0; reasons: list[str] = []; matched: list[str] = []; missing: list[str] = []; warnings: list[str] = []
    def add(label: str, weight: float, condition: bool, reason: str) -> None:
        nonlocal points
        if condition: points += weight; reasons.append("✓ " + reason); matched.append(label)
    add("country", weights.country, bool(profile.preferred_country and matches(profile.preferred_country, record.get("country"))), "Country preference matches")
    add("degree", weights.degree, bool(profile.preferred_degree and matches(profile.preferred_degree, record.get("degree"))), "Degree matches")
    field = record.get("field") or record.get("tags", [])
    add("field", weights.field, bool(profile.preferred_field and matches(profile.preferred_field, field)), "Field preference matches")
    funding = scholarship_value(record, "amount", "fundingType", "funding")
    add("funding", weights.funding, any(matches(preference, funding) for preference in profile.funding_preference), "Funding preference matches")
    required_cgpa = scholarship_value(record, "min_cgpa", "minCgpa")
    if profile.cgpa is not None and required_cgpa not in (None, ""):
        add("cgpa", weights.cgpa, profile.cgpa >= float(required_cgpa), "CGPA meets minimum")
    required_ielts = scholarship_value(record, "min_ielts", "minIelts", "ieltsScore")
    if record.get("ielts_required") is True or record.get("ieltsRequired") is True:
        if profile.english_medium and record.get("englishMediumAccepted") is True:
            add("ielts", weights.ielts, True, "English-medium qualification accepted")
        elif profile.ielts is None:
            missing.append("IELTS score required")
        elif required_ielts in (None, "") or profile.ielts >= float(required_ielts):
            add("ielts", weights.ielts, True, "IELTS requirement met")
        else: warnings.append("⚠ IELTS score below requirement")
    if record.get("research_required") is True or record.get("researchRequired") is True:
        if profile.research_interest: add("research", weights.research, True, "Research interest matches")
        else: warnings.append("⚠ Research experience recommended")
    scholarship_id = str(scholarship_value(record, "id", "documentId", "official_id", "officialId", "link") or "")
    return Recommendation(scholarship_id=scholarship_id, match_score=round(min(100.0, points * 100 / weights.total)) if weights.total else 0, reasons=tuple(reasons), matched_fields=tuple(matched), missing_requirements=tuple(missing), warnings=tuple(warnings))
