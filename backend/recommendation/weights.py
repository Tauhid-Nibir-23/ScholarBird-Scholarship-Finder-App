"""Configurable scoring weights; defaults total 100."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RecommendationWeights:
    country: float = 25.0
    degree: float = 20.0
    field: float = 20.0
    funding: float = 10.0
    cgpa: float = 10.0
    ielts: float = 10.0
    research: float = 5.0

    @property
    def total(self) -> float:
        return self.country + self.degree + self.field + self.funding + self.cgpa + self.ielts + self.research
