"""Field-of-study extraction.

The module recognises broad discipline families that the ScholarBird
catalogue cares about:

==================  ============================
Display label       :class:`FieldOfStudy`
==================  ============================
Computer Science    COMPUTER_SCIENCE
Information Tech.   INFORMATION_TECHNOLOGY
Engineering         ENGINEERING
Business            BUSINESS
Management          MANAGEMENT
Economics           ECONOMICS
Finance             FINANCE
Mathematics         MATHEMATICS
Science             SCIENCE
Biology             BIOLOGY
Chemistry           CHEMISTRY
Physics             PHYSICS
Medicine            MEDICINE
Public Health       PUBLIC_HEALTH
Law                 LAW
Arts & Humanities   ARTS_HUMANITIES
Social Sciences     SOCIAL_SCIENCES
Education           EDUCATION
Agriculture         AGRICULTURE
Environmental       ENVIRONMENTAL
Energy              ENERGY
Architecture        ARCHITECTURE
Communications      COMMUNICATIONS
Psychology          PSYCHOLOGY
Design              DESIGN
==================  ============================

The output is a :class:`Field` dataclass with a ``primary`` slot
(the first discipline mentioned) and an ``all_fields`` list (every
discipline found on the page, in source order). We also expose the
matched phrases for audit.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Sequence

from bs4 import BeautifulSoup

from .html import extract_text, find_section, strip_noise


# ---------------------------------------------------------------------------
# Field catalog
# ---------------------------------------------------------------------------


class FieldOfStudy(str, Enum):
    """Supported scholarship disciplines."""

    COMPUTER_SCIENCE = "Computer Science"
    INFORMATION_TECHNOLOGY = "Information Technology"
    ENGINEERING = "Engineering"
    BUSINESS = "Business"
    MANAGEMENT = "Management"
    ECONOMICS = "Economics"
    FINANCE = "Finance"
    MATHEMATICS = "Mathematics"
    SCIENCE = "Science"
    BIOLOGY = "Biology"
    CHEMISTRY = "Chemistry"
    PHYSICS = "Physics"
    MEDICINE = "Medicine"
    PUBLIC_HEALTH = "Public Health"
    LAW = "Law"
    ARTS_HUMANITIES = "Arts & Humanities"
    SOCIAL_SCIENCES = "Social Sciences"
    EDUCATION = "Education"
    AGRICULTURE = "Agriculture"
    ENVIRONMENTAL = "Environmental Studies"
    ENERGY = "Energy"
    ARCHITECTURE = "Architecture"
    COMMUNICATIONS = "Communications"
    PSYCHOLOGY = "Psychology"
    DESIGN = "Design"
    ALL = "All Fields"


# Aliases grouped for matching.
_FIELD_ALIASES: dict[FieldOfStudy, tuple[str, ...]] = {
    FieldOfStudy.COMPUTER_SCIENCE: (
        r"\bcomputer\s+science\b", r"\bcs\b", r"\bcse\b",
        r"\bcomputing\b", r"\bmachine\s+learning\b",
        r"\bartificial\s+intelligence\b", r"\bdata\s+science\b",
        r"\bsoftware\s+engineering\b",
    ),
    FieldOfStudy.INFORMATION_TECHNOLOGY: (
        r"\bit\b", r"\binfo(?:rmation)?\s*technology\b", r"\bict\b",
        r"\binformation\s*systems?\b", r"\bcybersecurity\b",
    ),
    FieldOfStudy.ENGINEERING: (
        r"\bengineering\b", r"\baerospace\b", r"\bmechanical\b",
        r"\belectrical\b", r"\bcivil\s+engineering\b",
        r"\bchemical\s+engineering\b", r"\bindustrial\s+engineering\b",
        r"\bbiomedical\s+engineering\b",
    ),
    FieldOfStudy.BUSINESS: (
        r"\bbusiness\s+(?:administration|analytics|studies)\b",
        r"\bbba\b", r"\bbba\s+students?\b",
        r"\bbusiness\s+management\b",
    ),
    FieldOfStudy.MANAGEMENT: (
        r"\bmanagement\b", r"\bmba\b", r"\bm\.?\s*b\.?\s*a\.?\b",
        r"\bproject\s+management\b", r"\bsupply\s+chain\b",
    ),
    FieldOfStudy.ECONOMICS: (
        r"\beconomics?\b", r"\becon\b", r"\beconometrics\b",
        r"\bdevelopment\s+economics\b",
    ),
    FieldOfStudy.FINANCE: (
        r"\bfinance\b", r"\bbanking\b", r"\baccounting\b",
        r"\bfinancial\s+engineering\b", r"\bfintech\b",
    ),
    FieldOfStudy.MATHEMATICS: (
        r"\bmathematics\b", r"\bmaths\b", r"\bapplied\s+mathematics?\b",
        r"\bstatistics?\b",
    ),
    FieldOfStudy.SCIENCE: (
        r"\bnatural\s+sciences?\b", r"\bscience\b", r"\bphysics\b",
    ),
    FieldOfStudy.BIOLOGY: (
        r"\bbiology\b", r"\bbehavioral\s+biology\b", r"\bmicrobiology\b",
        r"\bbiotechnology\b", r"\bgenetics?\b",
    ),
    FieldOfStudy.CHEMISTRY: (
        r"\bchemistry\b", r"\bchemical\s+sciences?\b",
        r"\bbiochemistry\b",
    ),
    FieldOfStudy.PHYSICS: (
        r"\bphysics\b", r"\bastrophysics\b", r"\bparticle\s+physics\b",
    ),
    FieldOfStudy.MEDICINE: (
        r"\bmedicine\b", r"\bmedical\b", r"\bmbbs\b",
        r"\bmd\b", r"\bm\.?\s*d\.?\b", r"\bsurgery\b",
        r"\bclinical\b",
    ),
    FieldOfStudy.PUBLIC_HEALTH: (
        r"\bpublic\s+health\b", r"\bepidemiology\b",
        r"\bnutrition\b", r"\bhealth\s+sciences?\b",
    ),
    FieldOfStudy.LAW: (
        r"\blaw\b", r"\bll\.?\s*b\.?\b", r"\bll\.?\s*m\.?\b",
        r"\bjd\b", r"\bj\.?\s*d\.?\b", r"\binternational\s+law\b",
        r"\blegal\s+studies?\b",
    ),
    FieldOfStudy.ARTS_HUMANITIES: (
        r"\bhumanities\b", r"\bart\s+history\b", r"\bphilosophy\b",
        r"\bhistory\b", r"\bliterature\b", r"\blinguistics\b",
        r"\benglish\s+literature\b", r"\barts\s+and\s+humanities\b",
        r"\barts\b",
    ),
    FieldOfStudy.SOCIAL_SCIENCES: (
        r"\bsocial\s+science(?:s)?\b", r"\bsociology\b",
        r"\bpolitical\s+science\b", r"\bpolitics\b",
        r"\binternational\s+relations\b", r"\bgeography\b",
        r"\b anthropology\b", r"\banthropology\b",
    ),
    FieldOfStudy.EDUCATION: (
        r"\beducation\b", r"\bteacher\s+training\b",
        r"\bpedagogy\b", r"\beducational\s+leadership\b",
    ),
    FieldOfStudy.AGRICULTURE: (
        r"\bagriculture\b", r"\bagricultural\s+sciences?\b",
        r"\bagronomy\b", r"\bfishery\b", r"\bforestry\b",
        r"\bfood\s+sciences?\b",
    ),
    FieldOfStudy.ENVIRONMENTAL: (
        r"\benvironmental\s+science\b", r"\bclimate\s+(?:change|science)\b",
        r"\bsustainability\b", r"\bconservation\b",
        r"\becology\b",
    ),
    FieldOfStudy.ENERGY: (
        r"\benergy\s+(?:engineering|studies|science|systems)\b",
        r"\brenewable\s+energy\b", r"\bsolar\s+energy\b",
        r"\bnuclear\s+engineering\b",
    ),
    FieldOfStudy.ARCHITECTURE: (
        r"\barchitecture\b", r"\barchitectural\s+design\b",
        r"\bplanning\b", r"\burban\s+planning\b",
    ),
    FieldOfStudy.COMMUNICATIONS: (
        r"\bcommunication(?:s)?\b", r"\bjournalism\b",
        r"\bmedia\s+studies\b", r"\bmass\s+communication\b",
        r"\b(?:digital\s+)?media\b",
    ),
    FieldOfStudy.PSYCHOLOGY: (
        r"\bpsychology\b", r"\bpsychiatry\b",
        r"\bcounseling\b", r"\bclinical\s+psychology\b",
    ),
    FieldOfStudy.DESIGN: (
        r"\b(?:graphic\s+design|industrial\s+design|interior\s+design"
        r"|product\s+design|fashion\s+design|ux\s+design|ui\s+design"
        r"|game\s+design)\b",
    ),
}


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class Field:
    """Field-of-study information extracted from the page."""

    primary: Optional[FieldOfStudy] = None
    all_fields: List[FieldOfStudy] = field(default_factory=list)
    evidence: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Section heading candidates
# ---------------------------------------------------------------------------

_HEADINGS: tuple[str, ...] = (
    "Field of Study",
    "Fields of Study",
    "Eligible Field",
    "Eligible Fields",
    "Discipline",
    "Subject",
    "Subject Area",
    "Programme Area",
    "Area of Study",
    "Areas of Study",
    "Study Area",
    "Study Areas",
    "Major",
    "Specialization",
    "Specialisation",
    "Eligible Programmes",
    "Programmes Available",
    "Programs Available",
)

_STOP_HEADINGS: tuple[str, ...] = (
    "Eligibility",
    "Application Procedure",
    "How to Apply",
    "Benefits",
    "Funding",
    "Deadline",
    "Contact",
    "Frequently Asked Questions",
    "FAQs",
    "FAQ",
)

#: Phrases that signal "any field is fine" — used to short-circuit the
#: extractor and produce ``FieldOfStudy.ALL``.
_ALL_FIELDS_PATTERNS: tuple[str, ...] = (
    r"\ball\s+(?:fields|disciplines|subjects|areas|majors"
    r"|study\s+areas)\b",
    r"\bany\s+(?:field|discipline|subject|major|programme)\b",
    r"\bopen\s+to\s+(?:all|any)\b",
    r"\bno\s+field\s+restriction\b",
    r"\ball\s+study\s+areas\b",
    r"\binterdisciplinary\b",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _clean(snippet: str) -> str:
    return re.sub(r"\s+", " ", snippet or "").strip()


def _compile_aliases() -> list[tuple[FieldOfStudy, list[re.Pattern]]]:
    compiled: list[tuple[FieldOfStudy, list[re.Pattern]]] = []
    for field_name, patterns in _FIELD_ALIASES.items():
        compiled.append(
            (
                field_name,
                [re.compile(p, re.I) for p in patterns],
            )
        )
    return compiled


_COMPILED = _compile_aliases()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_field(soup: BeautifulSoup) -> Field:
    """Return the fields of study found on ``soup``.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Populated :class:`Field`. ``primary`` is ``None`` when no
        match and no "all fields" phrase is found.
    """
    result = Field()
    if soup is None:
        return result

    cleaned = strip_noise(soup)
    page_text = extract_text(cleaned)
    if not page_text:
        return result

    # 1. Locate a fields-flavoured section.
    section_text = ""
    for heading in _HEADINGS:
        fragment = find_section(
            soup,
            [heading],
            stop_headings=list(_STOP_HEADINGS),
        )
        if fragment is not None:
            candidate = extract_text(fragment)
            if candidate:
                section_text = candidate
                break
    haystack = section_text or page_text

    # 2. "All fields" short-circuit.
    if any(
        re.search(pattern, haystack, re.I)
        for pattern in _ALL_FIELDS_PATTERNS
    ):
        result.primary = FieldOfStudy.ALL
        result.all_fields = [FieldOfStudy.ALL]
        result.evidence.append("ALL_FIELDS_DETECTED")
        return result

    # 3. Match field aliases.
    found: list[FieldOfStudy] = []
    evidence: list[str] = []

    # We match in two passes: prefer section text, fall back to page.
    order = (haystack, page_text) if haystack is not page_text else (page_text,)
    for source in order:
        for field_name, patterns in _COMPILED:
            for pattern in patterns:
                for match in pattern.finditer(source):
                    snippet = _clean(match.group(0))
                    if field_name in found:
                        break
                    found.append(field_name)
                    evidence.append(f"{field_name.value} :: {snippet}")
                    break  # one hit per alias is enough
        if found:
            break

    if found:
        result.all_fields = found
        result.primary = found[0]
        result.evidence = evidence
    return result


__all__ = ["Field", "FieldOfStudy", "extract_field"]
