"""DAAD-specific selectors for official programme detail pages."""

from __future__ import annotations

import re
from typing import Optional
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from .base_provider import ScholarshipProvider


class DaadProvider(ScholarshipProvider):
    name = "daad"
    domains = ("daad.de",)
    source_names = ("daad",)
    official_id_prefixes = ("daad-",)

    def _text_after_label(self, soup: BeautifulSoup, labels: tuple[str, ...]) -> Optional[str]:
        for node in soup.find_all(["dt", "th", "h2", "h3", "h4"]):
            label = node.get_text(" ", strip=True).lower()
            if any(candidate in label for candidate in labels):
                sibling = node.find_next_sibling(["dd", "td", "p", "div", "ul"])
                if sibling:
                    value = sibling.get_text(" ", strip=True)
                    if value:
                        return value
        return None

    def extract_description(self, soup: BeautifulSoup) -> Optional[str]:
        for selector in (".programme-description", ".course-description", "#description", "main article"):
            node = soup.select_one(selector)
            if node:
                text = node.get_text(" ", strip=True)
                if len(text) > 40:
                    return text
        return None

    def extract_deadline(self, soup: BeautifulSoup) -> Optional[str]:
        return self._text_after_label(soup, ("application deadline", "deadline"))

    def extract_funding(self, soup: BeautifulSoup) -> Optional[str]:
        text = soup.get_text(" ", strip=True).lower()
        if "monthly payments" in text or "monthly payment" in text:
            return "Living Allowance"
        if "fully funded" in text:
            return "Fully Funded"
        return None

    def extract_language_requirements(self, soup: BeautifulSoup) -> tuple[Optional[bool], Optional[bool]]:
        text = soup.get_text(" ", strip=True).lower()
        return (True if "ielts" in text else None, True if re.search(r"english[- ]medium.{0,60}(accepted|acceptable)", text) else None)

    def extract_university(self, soup: BeautifulSoup) -> Optional[str]:
        return self._text_after_label(soup, ("university", "institution", "host"))

    def extract_degree(self, soup: BeautifulSoup) -> Optional[str]:
        text = soup.get_text(" ", strip=True).lower()
        if "doctoral" in text or "phd" in text:
            return "PhD"
        if "postgraduate" in text or "master" in text:
            return "Postgraduate"
        if "undergraduate" in text or "bachelor" in text:
            return "Bachelors"
        return None

    def extract_field(self, soup: BeautifulSoup) -> Optional[str]:
        return self._text_after_label(soup, ("field of study", "subject area", "subject group"))

    def extract_image(self, soup: BeautifulSoup, page_url: str) -> Optional[str]:
        hero = soup.select_one(".hero img, .stage img, .banner img")
        if hero and hero.get("src"):
            value = urljoin(page_url, str(hero["src"]))
            return value if value.startswith("https://") else None
        return None

    def extract_tags(self, soup: BeautifulSoup) -> list[str]:
        text = soup.get_text(" ", strip=True).lower()
        return [tag for tag, marker in (("EPOS", "epos"), ("Research Grant", "research grant"), ("Short Course", "short course"), ("Study Scholarship", "study scholarship")) if marker in text]

    def extract_eligibility(self, soup: BeautifulSoup) -> Optional[str]:
        return self._text_after_label(soup, ("admission requirements", "requirements", "eligibility"))

    def extract_benefits(self, soup: BeautifulSoup) -> list[str]:
        text = soup.get_text(" ", strip=True).lower()
        return [label for label, marker in (("Living Allowance", "monthly payment"), ("Travel Grant", "travel allowance"), ("Health Insurance", "health insurance")) if marker in text]
