"""Chevening country/programme-page selectors and terminology mapping."""

from __future__ import annotations

import re
from typing import Optional

from bs4 import BeautifulSoup

from .base_provider import ScholarshipProvider


class CheveningProvider(ScholarshipProvider):
    name = "chevening"
    domains = ("chevening.org",)
    source_names = ("chevening",)
    official_id_prefixes = ("chevening-",)

    def _section(self, soup: BeautifulSoup, labels: tuple[str, ...]) -> Optional[str]:
        for heading in soup.find_all(["h2", "h3", "h4"]):
            if any(label in heading.get_text(" ", strip=True).lower() for label in labels):
                values = []
                for sibling in heading.find_next_siblings():
                    if sibling.name in {"h2", "h3", "h4"}:
                        break
                    value = sibling.get_text(" ", strip=True)
                    if value:
                        values.append(value)
                if values:
                    return " ".join(values)
        return None

    def extract_description(self, soup: BeautifulSoup) -> Optional[str]:
        return self._section(soup, ("about chevening", "chevening scholarships", "programme"))

    def extract_deadline(self, soup: BeautifulSoup) -> Optional[str]:
        return self._section(soup, ("timeline", "application dates", "deadline"))

    def extract_funding(self, soup: BeautifulSoup) -> Optional[str]:
        benefits = self._section(soup, ("benefits", "financial support", "what chevening covers")) or ""
        return "Fully Funded" if re.search(r"full financial support|fully funded", benefits, re.I) else None

    def extract_language_requirements(self, soup: BeautifulSoup) -> tuple[Optional[bool], Optional[bool]]:
        text = self._section(soup, ("requirements", "eligibility", "english language")) or ""
        return (True if re.search(r"\bielts\b", text, re.I) else None, True if re.search(r"english[- ]medium.{0,60}(accepted|acceptable)", text, re.I) else None)

    def extract_university(self, soup: BeautifulSoup) -> Optional[str]:
        return self._section(soup, ("university", "course choice"))

    def extract_degree(self, soup: BeautifulSoup) -> Optional[str]:
        text = soup.get_text(" ", strip=True).lower()
        return "Postgraduate" if "master" in text or "postgraduate" in text else None

    def extract_field(self, soup: BeautifulSoup) -> Optional[str]:
        return self._section(soup, ("course subject", "field of study"))

    def extract_image(self, soup: BeautifulSoup, page_url: str) -> Optional[str]:
        meta = soup.find("meta", attrs={"property": "og:image"})
        if meta and meta.get("content") and str(meta["content"]).startswith("https://"):
            return str(meta["content"])
        return None

    def extract_tags(self, soup: BeautifulSoup) -> list[str]:
        return ["Chevening", "Postgraduate"]

    def extract_eligibility(self, soup: BeautifulSoup) -> Optional[str]:
        return self._section(soup, ("eligibility", "requirements"))

    def extract_benefits(self, soup: BeautifulSoup) -> list[str]:
        text = self._section(soup, ("benefits", "financial support", "what chevening covers")) or ""
        pairs = (("Tuition Waiver", "tuition"), ("Living Allowance", "living allowance"), ("Travel Grant", "travel"), ("Health Insurance", "insurance"))
        return [label for label, marker in pairs if marker in text.lower()]
