"""Official-source plugins for international scholarship programmes.

These plugins only interpret HTML already fetched by the established pipeline;
they make no network requests and therefore reuse its robots, retry, timeout,
normalisation, lifecycle, search, and upload behaviour.
"""

from __future__ import annotations

import re
from typing import Optional
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from backend.provider_framework.capabilities import ProviderCapabilities
from backend.provider_framework.metadata import ProviderMetadata
from .base_provider import ScholarshipProvider


class OfficialInternationalProvider(ScholarshipProvider):
    """Shared deterministic selectors; each concrete class declares its source."""

    provider_metadata: ProviderMetadata
    capabilities = ProviderCapabilities(True, True, True, True, True, True, True, True, True, True)
    funding_terms: tuple[str, ...] = ("fully funded", "full scholarship", "tuition", "living allowance", "stipend")

    def _label_text(self, soup: BeautifulSoup, labels: tuple[str, ...]) -> Optional[str]:
        for node in soup.find_all(["dt", "th", "h2", "h3", "h4"]):
            if any(label in node.get_text(" ", strip=True).casefold() for label in labels):
                sibling = node.find_next_sibling(["dd", "td", "p", "div", "ul"])
                if sibling:
                    text = sibling.get_text(" ", strip=True)
                    if text: return text
        return None

    def extract_title(self, soup: BeautifulSoup) -> Optional[str]:
        heading = soup.find("h1")
        return heading.get_text(" ", strip=True) if heading else None

    def extract_description(self, soup: BeautifulSoup) -> Optional[str]:
        meta = soup.find("meta", attrs={"name": "description"})
        if meta and meta.get("content"): return str(meta["content"]).strip()
        main = soup.select_one("main article, main .content, article")
        text = main.get_text(" ", strip=True) if main else ""
        return text if len(text) >= 40 else None

    def extract_deadline(self, soup: BeautifulSoup) -> Optional[str]:
        return self._label_text(soup, ("application deadline", "closing date", "deadline", "key dates"))

    def extract_funding(self, soup: BeautifulSoup) -> Optional[str]:
        text = soup.get_text(" ", strip=True).casefold()
        if "fully funded" in text or "full financial support" in text: return "Fully Funded"
        if any(term in text for term in self.funding_terms): return self._label_text(soup, ("funding", "benefits", "financial support", "what is covered"))
        return None

    def extract_language_requirements(self, soup: BeautifulSoup) -> tuple[Optional[bool], Optional[bool]]:
        text = soup.get_text(" ", strip=True).casefold()
        return (True if "ielts" in text else None, True if re.search(r"english[- ]medium.{0,60}(accepted|acceptable)", text) else None)

    def extract_university(self, soup: BeautifulSoup) -> Optional[str]:
        return self._label_text(soup, ("host university", "host institution", "university", "institution"))

    def extract_degree(self, soup: BeautifulSoup) -> Optional[str]:
        text = soup.get_text(" ", strip=True).casefold()
        if "doctoral" in text or "phd" in text: return "PhD"
        if "master" in text or "postgraduate" in text: return "Postgraduate"
        if "undergraduate" in text or "bachelor" in text: return "Bachelors"
        return None

    def extract_field(self, soup: BeautifulSoup) -> Optional[str]:
        return self._label_text(soup, ("field of study", "eligible fields", "subject area", "priority areas"))

    def extract_image(self, soup: BeautifulSoup, page_url: str) -> Optional[str]:
        meta = soup.find("meta", attrs={"property": "og:image"})
        value = str(meta.get("content") or "") if meta else ""
        if value.startswith("https://"): return value
        hero = soup.select_one(".hero img, .banner img, main img")
        if hero and hero.get("src"):
            value = urljoin(page_url, str(hero["src"]))
            return value if value.startswith("https://") else None
        return None

    def extract_tags(self, soup: BeautifulSoup) -> list[str]:
        return [self.provider_metadata.provider_name]

    def extract_eligibility(self, soup: BeautifulSoup) -> Optional[str]:
        return self._label_text(soup, ("eligibility", "who can apply", "requirements", "applicant profile"))

    def extract_benefits(self, soup: BeautifulSoup) -> list[str]:
        text = soup.get_text(" ", strip=True).casefold()
        pairs = (("Tuition Waiver", "tuition"), ("Living Allowance", "living allowance"), ("Travel Grant", "travel"), ("Health Insurance", "health insurance"))
        return [label for label, term in pairs if term in text]


def _metadata(name: str, url: str, priority: int = 100) -> ProviderMetadata:
    return ProviderMetadata(name, "1.0", "official_public_source", url, priority, "daily", ProviderCapabilities(True, True, True, True, True, True, True, True, True, True).supported_fields())


class ErasmusMundusProvider(OfficialInternationalProvider):
    name = "erasmus_mundus"; domains = ("erasmus-plus.ec.europa.eu",); source_names = ("erasmus_mundus",); official_id_prefixes = ("erasmus-",); provider_metadata = _metadata("Erasmus Mundus", "https://erasmus-plus.ec.europa.eu")

class CommonwealthProvider(OfficialInternationalProvider):
    name = "commonwealth"; domains = ("cscuk.fcdo.gov.uk",); source_names = ("commonwealth",); official_id_prefixes = ("commonwealth-",); provider_metadata = _metadata("Commonwealth Scholarships", "https://cscuk.fcdo.gov.uk")

class FulbrightProvider(OfficialInternationalProvider):
    name = "fulbright"; domains = ("foreign.fulbrightonline.org", "fulbrightonline.org"); source_names = ("fulbright",); official_id_prefixes = ("fulbright-",); provider_metadata = _metadata("Fulbright", "https://foreign.fulbrightonline.org")

class AustraliaAwardsProvider(OfficialInternationalProvider):
    name = "australia_awards"; domains = ("dfat.gov.au",); source_names = ("australia_awards",); official_id_prefixes = ("australia-awards-",); provider_metadata = _metadata("Australia Awards", "https://www.dfat.gov.au", 90)

class MextProvider(OfficialInternationalProvider):
    name = "mext"; domains = ("mext.go.jp",); source_names = ("mext",); official_id_prefixes = ("mext-",); provider_metadata = _metadata("MEXT", "https://www.mext.go.jp")

class GksProvider(OfficialInternationalProvider):
    name = "gks"; domains = ("studyinkorea.go.kr",); source_names = ("gks",); official_id_prefixes = ("gks-",); provider_metadata = _metadata("Global Korea Scholarship", "https://www.studyinkorea.go.kr")

class CscChinaProvider(OfficialInternationalProvider):
    name = "csc_china"; domains = ("campuschina.org",); source_names = ("csc_china", "csc"); official_id_prefixes = ("csc-",); provider_metadata = _metadata("CSC China Scholarship", "https://www.campuschina.org")

class SwissExcellenceProvider(OfficialInternationalProvider):
    name = "swiss_excellence"; domains = ("sbfi.admin.ch",); source_names = ("swiss_excellence",); official_id_prefixes = ("swiss-",); provider_metadata = _metadata("Swiss Government Excellence Scholarships", "https://www.sbfi.admin.ch")
