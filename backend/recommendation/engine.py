"""Fast, in-memory, read-only scholarship recommendation engine."""

from __future__ import annotations

from datetime import date
from typing import Any, Iterable, Mapping, Optional

from .filters import deadline_date, reject_reason
from .models import Recommendation, UserProfile
from .scoring import score
from .weights import RecommendationWeights


class RecommendationEngine:
    def __init__(self, weights: Optional[RecommendationWeights] = None) -> None:
        self.weights = weights or RecommendationWeights()

    def recommend(self, scholarships: Iterable[Mapping[str, Any]], profile: UserProfile | Mapping[str, Any], *, limit: Optional[int] = None, today: Optional[date] = None) -> list[Recommendation]:
        """Filter then score records without mutating inputs or persisting data."""
        user = profile if isinstance(profile, UserProfile) else UserProfile.from_mapping(profile)
        ranked: list[tuple[Recommendation, date, str]] = []
        for record in scholarships:
            if reject_reason(record, user, today=today):
                continue
            result = score(record, user, self.weights)
            due = deadline_date(record.get("deadline")) or date.max
            newest = str(record.get("updatedAt") or record.get("updated_at") or record.get("createdAt") or "")
            ranked.append((result, due, newest))
        # Stable sorts encode the required order: highest score, nearest
        # deadline, then newest timestamp.
        ranked.sort(key=lambda item: item[2], reverse=True)
        ranked.sort(key=lambda item: item[1])
        ranked.sort(key=lambda item: item[0].match_score, reverse=True)
        output = [item[0] for item in ranked]
        return output[:limit] if limit is not None else output
