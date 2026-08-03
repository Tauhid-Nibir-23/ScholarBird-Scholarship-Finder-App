"""Top-level orchestrator for the production extraction engine.

The engine merges every module in :mod:`backend.parser.extractors` and
implements the priority order specified by the project documentation:

1. JSON-LD structured data (highest quality, publisher-authored).
2. OpenGraph + Twitter Card meta tags.
3. Standard HTML meta tags + page metadata.
4. Tables / definition lists.
5. Requirements / Eligibility sections.
6. FAQ / accordion sections.
7. Hero / banner images.
8. Fallback — sections, lists, page-wide text patterns.

The function returns a single :class:`ExtractedFields` instance with:

* Canonical Flutter storage slots: ``title``, ``description``,
  ``provider``, ``image``, ``country``, ``degree``, ``fields``,
  ``funding``, ``deadline``.
* Engine-only slots for transparency: ``amount``, ``currency``,
  ``benefits``, ``languageTests``, ``cgpa``, ``research``,
  ``university``, ``requirementsNotes``, ``evidenceLines``,
  ``imageCandidates``.

The engine is intentionally additive. It never mutates
:class:`parser.enrich.ScholarshipEnricher` and never invents values
when the source page lacks them. Existing fields already populated
by the scraper are preserved untouched.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Iterable, List, Mapping, MutableMapping, Optional

from bs4 import BeautifulSoup

from .deadline import Deadline, extract_deadline
from .degree import Degree, DegreeLevel, extract_degree
from .description import Description, clean_description
from .field import Field, FieldOfStudy, extract_field
from .funding import Funding, extract_funding
from .image import ImageResult, extract_images
from .jsonld import JsonLdDocument, extract_jsonld
from .metadata import PageMetadata, extract_metadata
from .opengraph import OgFields, extract_opengraph
from .requirements import Requirements, extract_requirements
from .university import University, extract_university


logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Fetched-page shape
# ---------------------------------------------------------------------------


@dataclass
class FetchedPage:
    """A page fetched from the network, plus the soup tree."""

    url: str
    final_url: Optional[str] = None
    html: str = ""
    status_code: Optional[int] = None
    content_type: Optional[str] = None
    from_cache: bool = False
    soup: Optional[BeautifulSoup] = None

    def ensure_soup(self, parser_factory=None) -> None:
        """Build the :class:`BeautifulSoup` tree lazily."""
        if self.soup is not None:
            return
        if not self.html:
            self.soup = BeautifulSoup("", "html.parser")
            return
        if parser_factory is None:
            from .html import parse_html

            self.soup = parse_html(self.html)
        else:
            self.soup = parser_factory(self.html)


# ---------------------------------------------------------------------------
# Extracted-fields shape
# ---------------------------------------------------------------------------


@dataclass
class ExtractedFields:
    """The complete set of extracted fields for a single scholarship."""

    # Canonical Flutter slots.
    title: Optional[str] = None
    description: Optional[str] = None
    provider: Optional[str] = None
    image: Optional[str] = None
    country: Optional[str] = None
    degree: Optional[str] = None
    fields: List[str] = field(default_factory=list)
    funding: Optional[str] = None

    # Engine-only slots.
    deadline: Optional[Deadline] = None
    amount: Optional[float] = None
    currency: Optional[str] = None
    benefits: List[str] = field(default_factory=list)
    languageTests: List[dict] = field(default_factory=list)
    cgpa: List[dict] = field(default_factory=list)
    research: dict = field(default_factory=dict)
    university: Optional[str] = None
    requirementsNotes: List[str] = field(default_factory=list)
    imageCandidates: List[str] = field(default_factory=list)
    evidenceLines: List[str] = field(default_factory=list)
    jsonld: Optional[JsonLdDocument] = None
    og: Optional[OgFields] = None
    metadata: Optional[PageMetadata] = None
    fullyFunded: bool = False

    def to_mapping(self, *, include_debug: bool = False) -> dict:
        """Return a flat dict shaped for the Firestore pipeline."""
        mapping: dict = {
            "title": self.title,
            "description": self.description,
            "provider": self.provider,
            "image": self.image,
            "country": self.country,
            "degree": self.degree,
            "fields": list(self.fields),
            "funding": self.funding,
        }
        if include_debug:
            mapping.update(
                {
                    "fullyFunded": self.fullyFunded,
                    "deadline": (
                        self.deadline.raw if self.deadline else None
                    ),
                    "amount": self.amount,
                    "currency": self.currency,
                    "benefits": list(self.benefits),
                    "languageTests": list(self.languageTests),
                    "cgpa": list(self.cgpa),
                    "research": dict(self.research),
                    "university": self.university,
                    "requirementsNotes": list(self.requirementsNotes),
                    "imageCandidates": list(self.imageCandidates),
                    "evidenceLines": list(self.evidenceLines),
                }
            )
        return mapping


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _evidence_add(
    target: List[str], *sources: Iterable[Optional[str]]
) -> None:
    for source in sources:
        if not source:
            continue
        for line in source:
            if line and line not in target:
                target.append(line)


def _labels_to_names(values: list) -> List[str]:
    """Convert enums to their ``value`` strings for storage."""
    return [v.value if hasattr(v, "value") else str(v) for v in values]


def _degree_to_storage(level: Optional[DegreeLevel]) -> Optional[str]:
    if level is None:
        return None
    return level.value if level is not DegreeLevel.UNKNOWN else None


def _field_to_storage(field_value: Optional[FieldOfStudy]) -> Optional[str]:
    if field_value is None:
        return None
    return field_value.value if field_value is not FieldOfStudy.ALL else "All Fields"


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------


@dataclass
class FieldExtractor:
    """Top-level orchestrator. Pass once, get a populated result."""

    jsonld: JsonLdDocument = field(default_factory=JsonLdDocument)
    og: OgFields = field(default_factory=OgFields)
    metadata: PageMetadata = field(default_factory=PageMetadata)
    requirements: Requirements = field(default_factory=Requirements)
    funding: Funding = field(default_factory=Funding)
    deadline: Deadline = field(default_factory=Deadline)
    university: University = field(default_factory=University)
    degree: Degree = field(default_factory=Degree)
    field_of_study: Field = field(default_factory=Field)
    description: Description = field(default_factory=Description)
    images: ImageResult = field(default_factory=ImageResult)

    # -------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------

    def extract(
        self,
        page: FetchedPage,
        *,
        fetcher: Optional[object] = None,
        validate_images: bool = True,
    ) -> ExtractedFields:
        """Run every extractor and return a populated result.

        Args:
            page: A populated :class:`FetchedPage`.
            fetcher: Optional network fetcher passed to image
                validation when ``validate_images=True``.
            validate_images: When ``True``, every image candidate is
                network-validated (HEAD probe, image content-type).
                When ``False`` (default), URLs are accepted on the
                strength of their scheme + path.

        Returns:
            A populated :class:`ExtractedFields` instance.
        """
        page.ensure_soup()
        if page.soup is None:
            page.soup = BeautifulSoup("", "html.parser")

        soup = page.soup
        final_url = page.final_url or page.url

        # Run every extractor in priority order.
        self.jsonld = extract_jsonld(soup)
        self.og = extract_opengraph(soup)
        self.metadata = extract_metadata(soup)
        self.requirements = extract_requirements(soup)
        self.funding = extract_funding(soup)
        self.deadline = extract_deadline(soup)
        self.university = extract_university(soup, final_url)
        self.degree = extract_degree(soup)
        self.field_of_study = extract_field(soup)
        self.description = clean_description(soup)
        self.images = extract_images(
            soup, final_url, fetcher=fetcher, validate=validate_images
        )

        return self._assemble()

    # -------------------------------------------------------------------
    # Internal assembly
    # -------------------------------------------------------------------

    def _assemble(self) -> ExtractedFields:
        result = ExtractedFields()

        # 1. Title priority order: JSON-LD → OG → Twitter → meta → <title>.
        title = (
            self._pick_text(
                [n.name for n in self.jsonld.nodes if n.name],
                og_title=self.og.title or self.og.twitter_title,
                meta_title=self.metadata.title,
            )
        )
        result.title = title

        # 2. Description priority order: clean summary → JSON-LD →
        #    OG → meta description.
        clean_desc = self.description.primary
        result.description = clean_desc or self._pick_description()

        # 3. Provider / university.
        result.provider = self._pick_provider()
        result.university = self.university.host

        # 4. Image priority order: JSON-LD → OG → Twitter → inline hero → img.
        result.image = self.images.best
        result.imageCandidates = list(self.images.candidates)

        # 5. Country fallback.
        result.country = self._pick_country()

        # 6. Degree + field of study.
        degree_levels = self.degree.levels
        if degree_levels:
            result.degree = _degree_to_storage(degree_levels[0])
        fields = _labels_to_names(self.field_of_study.all_fields)
        if fields:
            result.fields = fields

        # 7. Funding.
        result.funding = self.funding.funding
        result.fullyFunded = self.funding.fullyFunded
        result.benefits = list(self.funding.benefits)
        result.amount = self.funding.monthlyStipend or self.funding.annual_value
        result.currency = (
            self.funding.stipend_currency
            or self.funding.currency
        )

        # 8. Deadline.
        result.deadline = self.deadline

        # 9. Requirements summary (engine slots).
        result.languageTests = self._requirements_to_dicts()
        result.cgpa = [
            {
                "scale": entry.scale,
                "value": entry.value,
                "raw": entry.raw,
            }
            for entry in self.requirements.cgpa
        ]
        result.research = {
            "required": self.requirements.research.required,
            "proposal": self.requirements.research.proposal,
            "supervisor": self.requirements.research.supervisor,
            "publication": self.requirements.research.publication,
        }
        result.requirementsNotes = list(self.requirements.notes)

        # 10. Debug slots.
        result.jsonld = self.jsonld
        result.og = self.og
        result.metadata = self.metadata
        _evidence_add(
            result.evidenceLines,
            self.images.evidence,
            self.university.evidence,
            self.funding.notes,
            self.degree.evidence,
            self.field_of_study.evidence,
            self.requirements.research.evidence,
        )

        return result

    # -------------------------------------------------------------------
    # Pickers
    # -------------------------------------------------------------------

    def _pick_text(
        self,
        candidates: List[str],
        *,
        og_title: Optional[str] = None,
        meta_title: Optional[str] = None,
    ) -> Optional[str]:
        for value in candidates:
            if value:
                return value
        if og_title:
            return og_title
        if meta_title:
            return meta_title
        return None

    def _pick_description(self) -> Optional[str]:
        for node in self.jsonld.nodes:
            if node.description:
                return node.description
        if self.og.description:
            return self.og.description
        if self.og.twitter_description:
            return self.og.twitter_description
        if self.metadata.description:
            return self.metadata.description
        return self.description.summary

    def _pick_provider(self) -> Optional[str]:
        for node in self.jsonld.nodes:
            if node.provider_name:
                return node.provider_name
            if node.organization_name:
                return node.organization_name
        if self.university.provider:
            return self.university.provider
        if self.metadata.site_name:
            return self.metadata.site_name
        return None

    def _pick_country(self) -> Optional[str]:
        for node in self.jsonld.nodes:
            if node.location:
                return node.location
        # Try scraping the OG locale for a country code; we don't infer.
        if self.og.locale:
            return self.og.locale
        return None

    def _requirements_to_dicts(self) -> List[dict]:
        out: List[dict] = []
        for language in self.requirements.languages:
            scores: List[dict] = []
            for entry in language.min_scores:
                scores.append(
                    {
                        "test": entry.test,
                        "score": entry.score,
                        "section": entry.section,
                    }
                )
            out.append(
                {
                    "language": language.language,
                    "tests": language.tests,
                    "minScores": scores,
                    "mediumAccepted": language.medium_accepted,
                }
            )
        return out


# ---------------------------------------------------------------------------
# Convenience entry point
# ---------------------------------------------------------------------------


def extract_fields_from_html(
    html: str,
    page_url: Optional[str] = None,
    *,
    existing: Optional[MutableMapping[str, Any]] = None,
    fetcher: Optional[object] = None,
    validate_images: bool = True,
) -> ExtractedFields:
    """Parse ``html`` and return canonical fields.

    Args:
        html: Raw HTML body.
        page_url: Final URL the page was loaded from.
        existing: Optional existing dict to merge *into* without overwriting.
            Used by :class:`parser.enrich.ScholarshipEnricher` to add new
            engine fields on top of the values it has already filled.
        fetcher: Optional network fetcher for image validation.
        validate_images: When ``True``, every image candidate is
            network-validated.

    Returns:
        Populated :class:`ExtractedFields`.
    """
    page = FetchedPage(
        url=page_url or "",
        final_url=page_url or "",
        html=html,
    )
    extractor = FieldExtractor()
    result = extractor.extract(
        page, fetcher=fetcher, validate_images=validate_images
    )

    if existing is not None:
        # Apply on top of existing fields — never overwrite.
        for key, value in result.to_mapping(include_debug=False).items():
            if value in (None, [], "") and key in existing:
                continue
            existing[key] = value
        existing["_engine"] = result.to_mapping(include_debug=True)
    return result


__all__ = [
    "ExtractedFields",
    "FetchedPage",
    "FieldExtractor",
    "extract_fields_from_html",
]
