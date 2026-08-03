"""Lightweight pre-normalisation quality gate for scholarship records."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Mapping

_NON_SCHOLARSHIP = re.compile(
    r"\b(news|announcement|guide|faq|search|directory|database|index|"
    r"category|navigation|information|important information|programme list)\b",
    re.I,
)
_FUNDING_SIGNALS = re.compile(
    r"\b(scholarship|fellowship|grant|funding|stipend|award|bursary)\b",
    re.I,
)
_URL = re.compile(r"^https?://\S+$", re.I)


@dataclass(frozen=True)
class QualityResult:
    accepted: bool
    score: int
    reason: str = ""


def assess_scholarship_quality(record: Mapping[str, Any], threshold: int = 60) -> QualityResult:
    """Score a source record and reject non-scholarship/navigation content."""
    title = str(record.get("title") or "").strip()
    description = str(record.get("description") or "").strip()
    apply_url = str(record.get("apply_url") or record.get("link") or "").strip()
    combined = f"{title} {description}"
    if len(title) < 8:
        return QualityResult(False, 0, "title is not meaningful")
    if not str(record.get("country") or "").strip() or not str(record.get("degree") or "").strip():
        return QualityResult(False, 0, "missing academic opportunity metadata")
    if not str(record.get("deadline") or "").strip():
        return QualityResult(False, 0, "missing application deadline")
    if _NON_SCHOLARSHIP.search(title):
        return QualityResult(False, 0, "non-scholarship title")
    if not _URL.match(apply_url):
        return QualityResult(False, 0, "missing official application URL")
    score = 25 + 35
    if len(description.split()) >= 12:
        score += 20
    if _FUNDING_SIGNALS.search(combined):
        score += 20
    if _NON_SCHOLARSHIP.search(description):
        score -= 30
    return QualityResult(score >= threshold, score, "quality score below threshold")


__all__ = ["QualityResult", "assess_scholarship_quality"]
