"""Capability discovery from the existing provider method contract."""

from __future__ import annotations

from dataclasses import dataclass

from backend.parser.providers.base_provider import ScholarshipProvider


@dataclass(frozen=True)
class ProviderCapabilities:
    supports_images: bool = False
    supports_deadlines: bool = False
    supports_funding: bool = False
    supports_country: bool = False
    supports_degree: bool = False
    supports_tags: bool = False
    supports_description: bool = False
    supports_university: bool = False
    supports_apply_url: bool = False
    supports_official_id: bool = False

    def supported_fields(self) -> tuple[str, ...]:
        return tuple(name.removeprefix("supports_") for name, enabled in self.__dict__.items() if enabled)

    @classmethod
    def from_provider(cls, provider: ScholarshipProvider) -> "ProviderCapabilities":
        provider_type = type(provider)
        overridden = lambda method: getattr(provider_type, method) is not getattr(ScholarshipProvider, method)
        return cls(
            supports_images=overridden("extract_image"), supports_deadlines=overridden("extract_deadline"),
            supports_funding=overridden("extract_funding"), supports_country=bool(provider.domains),
            supports_degree=overridden("extract_degree"), supports_tags=overridden("extract_tags"),
            supports_description=overridden("extract_description"), supports_university=overridden("extract_university"),
            supports_apply_url=bool(provider.domains), supports_official_id=bool(provider.official_id_prefixes),
        )
