"""Contracts and discovery for source-specific extraction plugins.

Providers are intentionally read-only: they consume already-fetched HTML and
return only explicitly evidenced values.  The caller decides whether an empty
model field may be filled, so no plugin can replace scraper or generic values.
"""

from __future__ import annotations

from dataclasses import dataclass, field as dataclass_field
from typing import Optional
from urllib.parse import urlparse

from bs4 import BeautifulSoup


@dataclass
class ProviderExtraction:
    """Provider values that can be additively merged into a record."""

    title: Optional[str] = None
    description: Optional[str] = None
    deadline: Optional[str] = None
    funding: Optional[str] = None
    ielts_required: Optional[bool] = None
    english_medium_accepted: Optional[bool] = None
    university: Optional[str] = None
    degree: Optional[str] = None
    field: Optional[str] = None
    image: Optional[str] = None
    tags: list[str] = dataclass_field(default_factory=list)
    eligibility: Optional[str] = None
    benefits: list[str] = dataclass_field(default_factory=list)


class ScholarshipProvider:
    """Base class for source plugins; methods return ``None`` by default."""

    name = "generic"
    domains: tuple[str, ...] = ()
    source_names: tuple[str, ...] = ()
    official_id_prefixes: tuple[str, ...] = ()

    def matches(self, *, source: str, url: str, official_id: Optional[str]) -> bool:
        source_value = (source or "").strip().lower()
        if source_value in self.source_names:
            return True
        identity = (official_id or "").strip().lower()
        if any(identity.startswith(prefix) for prefix in self.official_id_prefixes):
            return True
        host = (urlparse(url).hostname or "").lower()
        return any(host == domain or host.endswith("." + domain) for domain in self.domains)

    def extract_title(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_description(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_deadline(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_funding(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_language_requirements(self, soup: BeautifulSoup) -> tuple[Optional[bool], Optional[bool]]: return None, None
    def extract_university(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_degree(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_field(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_image(self, soup: BeautifulSoup, page_url: str) -> Optional[str]: return None
    def extract_tags(self, soup: BeautifulSoup) -> list[str]: return []
    def extract_eligibility(self, soup: BeautifulSoup) -> Optional[str]: return None
    def extract_benefits(self, soup: BeautifulSoup) -> list[str]: return []

    def extract(self, html: str, page_url: str) -> ProviderExtraction:
        soup = BeautifulSoup(html or "", "html.parser")
        ielts, medium = self.extract_language_requirements(soup)
        return ProviderExtraction(
            title=self.extract_title(soup), description=self.extract_description(soup),
            deadline=self.extract_deadline(soup), funding=self.extract_funding(soup),
            ielts_required=ielts, english_medium_accepted=medium,
            university=self.extract_university(soup), degree=self.extract_degree(soup),
            field=self.extract_field(soup), image=self.extract_image(soup, page_url),
            tags=self.extract_tags(soup), eligibility=self.extract_eligibility(soup),
            benefits=self.extract_benefits(soup),
        )


def detect_provider(*, source: str, url: str, official_id: Optional[str] = None) -> Optional[ScholarshipProvider]:
    """Return the matched provider or ``None`` so generic extraction remains fallback."""
    from .chevening import CheveningProvider
    from .daad import DaadProvider

    for provider_type in (DaadProvider, CheveningProvider):
        provider = provider_type()
        if provider.matches(source=source, url=url, official_id=official_id):
            return provider
    return None
