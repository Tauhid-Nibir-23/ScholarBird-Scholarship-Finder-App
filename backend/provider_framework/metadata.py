"""Metadata adapter for existing and future provider plugins."""

from __future__ import annotations

from dataclasses import dataclass

from backend.parser.providers.base_provider import ScholarshipProvider
from .capabilities import ProviderCapabilities


@dataclass(frozen=True)
class ProviderMetadata:
    provider_name: str
    provider_version: str
    provider_type: str
    base_url: str
    priority: int
    update_frequency: str
    supported_fields: tuple[str, ...]


def metadata_for(provider: ScholarshipProvider) -> ProviderMetadata:
    """Return declared metadata, or a safe adapter for legacy plugins."""
    declared = getattr(provider, "provider_metadata", None)
    if isinstance(declared, ProviderMetadata): return declared
    capability = ProviderCapabilities.from_provider(provider)
    domain = provider.domains[0] if provider.domains else ""
    return ProviderMetadata(provider_name=provider.name, provider_version=str(getattr(provider, "version", "1.0")), provider_type="scholarship_provider", base_url=f"https://{domain}" if domain else "", priority=int(getattr(provider, "priority", 100)), update_frequency=str(getattr(provider, "update_frequency", "daily")), supported_fields=capability.supported_fields())
