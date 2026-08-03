"""Pure, fast search-index generation with no persistence side effects."""

from __future__ import annotations

import re
from datetime import date
from typing import Any, Iterable, Mapping

from backend.recommendation import RecommendationEngine, UserProfile
from backend.recommendation.filters import deadline_date

_WORD_RE = re.compile(r"[^a-z0-9]+")
_STOP_WORDS = frozenset({"a", "an", "the", "and", "or", "of", "for", "with", "to", "in", "on", "at", "by", "from", "is", "are", "be", "this", "that", "these", "those", "etc", "via", "your", "you", "our", "their"})
_SEARCH_FIELDS = ("title", "description", "country", "degree", "field", "amount", "funding", "fundingType", "university", "tags", "eligibility")
_RANKER = RecommendationEngine()


def normalise(value: Any) -> str:
    """Return a lowercase punctuation-free value suitable for exact search."""
    text = str(value or "").casefold().replace("'", "").replace("’", "")
    return " ".join(_WORD_RE.sub(" ", text).split())


def _values(record: Mapping[str, Any], fields: Iterable[str]) -> list[str]:
    values: list[str] = []
    for field in fields:
        raw = record.get(field)
        if isinstance(raw, (list, tuple, set)):
            values.extend(normalise(item) for item in raw if normalise(item))
        else:
            value = normalise(raw)
            if value:
                values.append(value)
    return values


def _unique(values: Iterable[str], limit: int) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value and value not in seen:
            seen.add(value); result.append(value)
            if len(result) == limit: break
    return result


def _ranking_score(record: Mapping[str, Any]) -> int:
    """Reuse RecommendationEngine with deterministic, record-evidenced inputs."""
    funding = record.get("amount") or record.get("funding") or record.get("fundingType")
    profile = UserProfile(
        preferred_country=str(record.get("country") or "") or None,
        preferred_degree=str(record.get("degree") or "") or None,
        preferred_field=str(record.get("field") or "") or None,
        cgpa=100.0, ielts=9.0, english_medium=True, research_interest=True,
        funding_preference=(str(funding),) if funding else (),
    )
    ranked = _RANKER.recommend([record], profile, limit=1, today=date.min)
    return ranked[0].match_score if ranked else 0


def build_search_index(record: Mapping[str, Any]) -> dict[str, Any]:
    """Create only additional indexed fields; never mutate ``record``."""
    title = normalise(record.get("title")); university = normalise(record.get("university"))
    country = normalise(record.get("country")); degree = normalise(record.get("degree"))
    field = normalise(record.get("field")); funding = normalise(record.get("amount") or record.get("funding") or record.get("fundingType"))
    phrases = _values(record, _SEARCH_FIELDS)
    words = [word for phrase in phrases for word in phrase.split()]
    search_tokens = _unique([*phrases, *words], 150)
    keywords = _unique((word for word in words if len(word) > 1 and word not in _STOP_WORDS), 30)
    deadline = deadline_date(record.get("deadline"))
    return {
        "search_tokens": search_tokens,
        "normalized_title": title,
        "normalized_university": university,
        "normalized_country": country,
        "normalized_degree": degree,
        "normalized_field": field,
        "normalized_funding": funding,
        "keywords": keywords,
        "ranking_score": _ranking_score(record),
        "filter_index": {
            "country": country, "degree": degree, "field": field, "funding": funding,
            "deadline_year": deadline.year if deadline else None,
            "deadline_month": deadline.month if deadline else None,
            "fullyFunded": bool(record.get("fullyFunded", record.get("fully_funded", False))),
            "ieltsRequired": bool(record.get("ieltsRequired", record.get("ielts_required", False))),
            "englishMediumAccepted": bool(record.get("englishMediumAccepted", record.get("english_medium_accepted", False))),
            "researchRequired": bool(record.get("researchRequired", record.get("research_required", False))),
        },
    }
