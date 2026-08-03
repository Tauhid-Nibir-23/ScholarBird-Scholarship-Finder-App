"""Shared provider validation before a provider enters a pipeline."""

from __future__ import annotations

from dataclasses import dataclass

from backend.parser.providers.base_provider import ScholarshipProvider
from .capabilities import ProviderCapabilities
from .metadata import ProviderMetadata, metadata_for


@dataclass(frozen=True)
class ProviderValidation:
    valid: bool
    reasons: tuple[str, ...] = ()
    metadata: ProviderMetadata | None = None
    capabilities: ProviderCapabilities | None = None


def validate_provider(provider: ScholarshipProvider) -> ProviderValidation:
    reasons: list[str] = []
    if not isinstance(provider, ScholarshipProvider): return ProviderValidation(False, ("Provider must inherit ScholarshipProvider",))
    metadata = metadata_for(provider); capabilities = ProviderCapabilities.from_provider(provider)
    if not metadata.provider_name or metadata.provider_name == "generic": reasons.append("provider_name is required")
    if not metadata.base_url.startswith("https://"): reasons.append("base_url must be HTTPS")
    if metadata.priority < 0: reasons.append("priority must be non-negative")
    if not metadata.supported_fields: reasons.append("at least one capability is required")
    if not provider.source_names and not provider.domains and not provider.official_id_prefixes: reasons.append("provider needs a detection identity")
    return ProviderValidation(not reasons, tuple(reasons), metadata, capabilities)
