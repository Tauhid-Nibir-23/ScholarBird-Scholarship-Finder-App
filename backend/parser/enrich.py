"""Cached, read-only official-page enrichment for scholarship records.

The legacy regex-based extraction (image / IELTS / MOI / research / CGPA /
backlogs / funding) is preserved verbatim. A new
:class:`backend.parser.extractors.FieldExtractor` is invoked additively after
the regex pass: it surfaces high-quality values from JSON-LD, OpenGraph,
Twitter cards, schema.org structured data, tables, FAQ sections, and
definition lists. The engine never overwrites a non-empty field already
populated by the scraper or the legacy regex pass; it only fills empty
slots on the :class:`Scholarship` record and surfaces engine-only debug
data on the enricher instance.
"""

from __future__ import annotations

import logging
import re
from dataclasses import replace
from typing import Any, Dict, Optional
from urllib.parse import urljoin, urlparse

import httpx

from backend.models.scholarship import Scholarship

_logger = logging.getLogger(__name__)

try:  # The engine is a pure-additive dependency; legacy paths still work.
    from backend.parser.extractors import extract_fields_from_html
except Exception:  # pragma: no cover - defensive import guard
    extract_fields_from_html = None  # type: ignore[assignment]

try:  # The robust extractor is a pure-additive dependency; legacy paths still work.
    from backend.parser.extractors import extract_robust_images
except Exception:  # pragma: no cover - defensive import guard
    extract_robust_images = None  # type: ignore[assignment]

_IMAGE_META = re.compile(r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]+content=["\']([^"\']+)', re.I)
_IELTS = re.compile(r'\bIELTS\b[^0-9]{0,24}(\d(?:\.\d)?)', re.I)
_NEG_IELTS = re.compile(r'IELTS.{0,40}(?:not required|waived|not needed)', re.I)
_MOI = re.compile(r'(?:medium of instruction|english medium|MOI)', re.I)
_RESEARCH = re.compile(r'(?:research proposal|research experience|supervisor|publication).{0,30}(?:required|must)', re.I)
_CGPA = re.compile(r'(?:minimum )?(?:CGPA|GPA).{0,16}(\d(?:\.\d+)?)', re.I)
_BACKLOGS = re.compile(r'(?:maximum|up to)?\s*(\d+)\s*(?:backlogs|arrears|failed courses)', re.I)
_FUNDING = re.compile(r'(fully funded|partial(?:ly)? funded|tuition(?: fee)?(?: only)?|monthly stipend|living allowance|travel grant|research grant)', re.I)
_TAG = re.compile(r'<[^>]+>')


class ScholarshipEnricher:
    """Fetch each official URL once and fill only fields proved by its page."""

    def __init__(self) -> None:
        self._cache: Dict[str, str] = {}
        self._client = httpx.Client(timeout=15.0, follow_redirects=True)
        # Debug payload captured by the production extraction engine. Exposed
        # on the enricher so downstream code (or tests) can inspect the
        # structured fields the engine produced without mutating the
        # frozen :class:`Scholarship` record.
        self.last_engine_debug: Optional[Dict[str, Any]] = None

    def enrich(self, record: Scholarship) -> Scholarship:
        url = record.apply_url or record.link
        if not url or not url.startswith("https://"):
            return record
        html = self._fetch(url)
        if not html:
            return record
        text = re.sub(r'\s+', ' ', _TAG.sub(' ', html)).strip()
        image = record.image or self._image_url(html, url)
        ielts_required = record.ielts_required or bool(_IELTS.search(text))
        if _NEG_IELTS.search(text):
            ielts_required = False
        english_medium = record.english_medium_accepted
        if english_medium is None and _MOI.search(text):
            english_medium = True
        research = record.research_required or bool(_RESEARCH.search(text))
        cgpa = record.min_cgpa if record.min_cgpa is not None else self._number(_CGPA, text)
        backlogs = record.max_backlogs if record.max_backlogs else self._integer(_BACKLOGS, text)
        funding = record.amount
        match = _FUNDING.search(text)
        if (not funding or funding == "Unknown") and match:
            funding = match.group(1).title()

        # ------------------------------------------------------------------
        # Production extraction engine (additive layer)
        # ------------------------------------------------------------------
        # The engine re-parses the same HTML with the priority-ordered
        # extractors (JSON-LD → OG → Twitter → standard HTML → tables →
        # DLs → requirements → FAQ → hero → fallback). It only fills
        # slots that are still empty on the record and it never overwrites
        # values already produced by the scraper or the legacy regex
        # pass. Failures are logged and swallowed so the legacy path
        # remains the source of truth.
        description = record.description
        university = record.university
        field_value = record.field
        degree = record.degree
        country = record.country
        title = record.title
        cgpa_scale = record.cgpa_scale
        fully_funded = record.fully_funded
        if extract_fields_from_html is not None:
            try:
                existing_payload: Dict[str, Any] = {
                    "image": image,
                    "ielts_required": ielts_required,
                    "english_medium_accepted": english_medium,
                    "research_required": research,
                    "min_cgpa": cgpa,
                    "max_backlogs": backlogs,
                    "amount": funding,
                    "description": description,
                    "university": university,
                    "field": field_value,
                    "degree": degree,
                    "country": country,
                    "title": title,
                }
                extracted = extract_fields_from_html(
                    html,
                    page_url=url,
                    existing=existing_payload,
                    fetcher=self._client,
                )
                debug = extracted.to_mapping(include_debug=True)
                self.last_engine_debug = debug

                # Image: only adopt the engine's pick when no image was
                # already supplied by the scraper or the legacy regex.
                if not image:
                    candidate = extracted.image
                    if candidate:
                        image = candidate

                # Description: adopt the engine's clean description when
                # the existing record's description is empty or matches
                # the legacy placeholder.
                if not description or description.strip() in {"", "Unknown"}:
                    if extracted.description:
                        description = extracted.description

                # University / provider: only fill when empty.
                if not university and extracted.university:
                    university = extracted.university
                if not university and extracted.provider:
                    university = extracted.provider

                # Field of study: model slots are a single string.
                if (not field_value or field_value.strip() in {"", "Unknown"}) and extracted.fields:
                    field_value = extracted.fields[0]

                # Degree level: only fill when missing.
                if (not degree or degree.strip() in {"", "Unknown"}) and extracted.degree:
                    degree = extracted.degree

                # Country: only fill when missing.
                if (not country or country.strip() in {"", "Unknown"}) and extracted.country:
                    country = extracted.country

                # Title: only fill when missing, and never overwrite a
                # non-empty scraper title.
                if (not title or title.strip() in {"", "Unknown"}) and extracted.title:
                    title = extracted.title

                # Funding: prefer the engine's canonical string when the
                # existing amount is empty or placeholder.
                if (not funding or funding == "Unknown") and extracted.funding:
                    funding = extracted.funding

                # IELTS / research / english-medium: the engine surfaces
                # the same boolean hints; only adopt when the legacy regex
                # left the field unset.
                if not ielts_required and ielts_required is False:
                    language_tests = debug.get("languageTests") or []
                    if language_tests:
                        # If the engine detected a positive mention of an
                        # English test, adopt the True value.
                        ielts_required = True
                if not research and not research is False:
                    research_block = debug.get("research") or {}
                    if research_block.get("required"):
                        research = True
                if english_medium is None:
                    language_tests = debug.get("languageTests") or []
                    if language_tests:
                        # Engine found language tests; do not assume MOI
                        # so we leave the field at None to preserve the
                        # legacy default of True.
                        english_medium = None

                # Fully funded flag: only adopt when True.
                if not fully_funded and debug.get("fullyFunded"):
                    fully_funded = True

                # CGPA: engine entries are a list of dicts; only adopt
                # the first ``value`` when the model slot is empty.
                if cgpa is None:
                    cgpa_entries = debug.get("cgpa") or []
                    for entry in cgpa_entries:
                        if isinstance(entry, dict) and entry.get("value") is not None:
                            try:
                                cgpa = float(entry["value"])
                                scale = entry.get("scale")
                                if isinstance(scale, (int, float)):
                                    cgpa_scale = float(scale)
                                break
                            except (TypeError, ValueError):
                                continue

            except Exception as exc:  # noqa: BLE001 - defensive
                _logger.debug(
                    "Extraction engine failed for %s: %s",
                    getattr(record, "title", "?"),
                    exc,
                )
                self.last_engine_debug = None

        # ------------------------------------------------------------------
        # Robust image fallback (additive layer)
        # ------------------------------------------------------------------
        # Runs only when the legacy regex, the modern engine, and any
        # scraper-supplied value have all left ``image`` empty. The robust
        # extractor understands ``<picture>``/``<source srcset>``,
        # ``img[srcset]``, and the expanded hero/featured class
        # whitelist. It never overwrites a non-empty ``image`` value.
        if not image and extract_robust_images is not None and html:
            try:
                from bs4 import BeautifulSoup as _BS4  # local import: optional

                robust_soup = _BS4(html, "html.parser")
                robust_result = extract_robust_images(
                    robust_soup,
                    page_url=url,
                    fetcher=self._client,
                    validate=False,
                )
                if robust_result.best:
                    image = robust_result.best
            except Exception as exc:  # noqa: BLE001 - defensive
                _logger.debug(
                    "Robust image extractor failed for %s: %s",
                    getattr(record, "title", "?"),
                    exc,
                )

        return replace(
            record,
            title=title,
            description=description,
            country=country,
            degree=degree,
            field=field_value,
            amount=funding,
            image=image,
            min_cgpa=cgpa,
            cgpa_scale=cgpa_scale,
            max_backlogs=backlogs or 0,
            english_medium_accepted=english_medium if english_medium is not None else True,
            ielts_required=ielts_required,
            research_required=research,
            fully_funded=fully_funded,
            university=university,
        )

    def _fetch(self, url: str) -> str:
        if url not in self._cache:
            try:
                response = self._client.get(url)
                self._cache[url] = response.text if response.status_code == 200 else ""
            except httpx.HTTPError:
                self._cache[url] = ""
        return self._cache[url]

    @staticmethod
    def _image_url(html: str, base: str) -> Optional[str]:
        match = _IMAGE_META.search(html)
        if not match:
            return None
        url = urljoin(base, match.group(1).strip())
        return url if urlparse(url).scheme == "https" else None

    @staticmethod
    def _number(pattern: re.Pattern[str], text: str) -> Optional[float]:
        match = pattern.search(text)
        return float(match.group(1)) if match else None

    @staticmethod
    def _integer(pattern: re.Pattern[str], text: str) -> Optional[int]:
        match = pattern.search(text)
        return int(match.group(1)) if match else None
