"""Shared provider compliance suite usable by every future plugin."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from backend.parser.providers.base_provider import ScholarshipProvider
from .validation import ProviderValidation, validate_provider


@dataclass(frozen=True)
class ConformanceResult:
    provider_name: str
    passed: bool
    validation: ProviderValidation


def run_conformance_suite(providers: Iterable[ScholarshipProvider]) -> list[ConformanceResult]:
    """Validate every provider against one shared, discovery-independent suite."""
    results: list[ConformanceResult] = []
    for provider in providers:
        validation = validate_provider(provider)
        results.append(ConformanceResult(provider.name, validation.valid, validation))
    return results
