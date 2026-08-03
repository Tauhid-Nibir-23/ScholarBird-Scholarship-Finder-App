"""Reusable normalisation helpers for raw scholarship records.

This module is the canonical home for every transformation that turns
messy, upstream-produced fields into the clean, canonical shape the
rest of the backend (and the Flutter admin app) expects.

Design rules
------------

* Every helper is a **pure function** — no side effects, no I/O.
* Inputs are accepted as plain ``str`` (or ``None``); helpers always
  return a value of the documented type. They never raise for
  "unparseable" input — they return the documented sentinel and let
  the caller decide what to do.
* The mapping tables are exposed as module-level constants so tests
  and other modules can inspect them.
* The package-level entry point :func:`normalize_scholarship` applies
  every transformation in a single pass and returns a **new** dict,
  leaving the input untouched.

The set of transformations is intentionally narrow:

1. Country :func:`normalize_country`
2. Degree :func:`normalize_degree`
3. Funding :func:`normalize_funding`
4. Deadline :func:`normalize_deadline`
5. Free-text cleaning :func:`clean_text`
"""

from __future__ import annotations

import re
from typing import Any, Dict, Optional

from dateutil import parser as _date_parser

from backend.core.logger import get_logger

_logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Country normalisation
# ---------------------------------------------------------------------------

#: Mapping from raw country name to canonical country name. The keys
#: are matched case-insensitively after whitespace is collapsed.
COUNTRY_ALIASES: Dict[str, str] = {
    "germany": "Germany",
    "federal republic of germany": "Germany",
    "bundesrepublik deutschland": "Germany",
    "deutschland": "Germany",
    "de": "Germany",

    "united states of america": "USA",
    "united states": "USA",
    "usa": "USA",
    "us": "USA",
    "u.s.a": "USA",
    "america": "USA",

    "united kingdom": "United Kingdom",
    "united kingdom of great britain": "United Kingdom",
    "united kingdom of great britain and northern ireland": "United Kingdom",
    "uk": "United Kingdom",
    "great britain": "United Kingdom",
    "england": "United Kingdom",
    "britain": "United Kingdom",

    "netherlands": "Netherlands",
    "the netherlands": "Netherlands",
    "holland": "Netherlands",

    "uae": "UAE",
    "united arab emirates": "UAE",
}


def normalize_country(value: Optional[str]) -> Optional[str]:
    """Return the canonical country name for ``value``.

    The lookup is case-insensitive and whitespace-tolerant. Unknown
    inputs are returned with whitespace stripped and title-cased so
    the rest of the pipeline still has something usable.

    Args:
        value: Raw country string from an upstream source.

    Returns:
        Canonical country name, or ``None`` when ``value`` is
        ``None`` / empty.
    """
    if value is None:
        return None
    cleaned = clean_text(value)
    if not cleaned:
        return None
    key = cleaned.lower().strip()
    if key in COUNTRY_ALIASES:
        return COUNTRY_ALIASES[key]
    # Unknown: title-case but keep short words (UK, USA) as-is.
    if len(cleaned) <= 4 and cleaned.isupper():
        return cleaned
    return cleaned.title()


# ---------------------------------------------------------------------------
# Degree normalisation
# ---------------------------------------------------------------------------

#: Canonical degree names.
DEGREE_BACHELORS: str = "Bachelors"
DEGREE_MASTERS: str = "Masters"
DEGREE_PHD: str = "PhD"
DEGREE_POSTDOC: str = "Postdoctoral"

#: Words that individually map to a canonical degree. The order
#: matters: longer / more specific phrases are checked first.
_DEGREE_RULES: tuple[tuple[str, str], ...] = (
    # Postdoctoral
    ("postdoctoral", DEGREE_POSTDOC),
    ("post-doc", DEGREE_POSTDOC),
    ("post doc", DEGREE_POSTDOC),
    ("postdoc", DEGREE_POSTDOC),

    # PhD / doctorate
    ("doctoral candidate", DEGREE_PHD),
    ("phd candidate", DEGREE_PHD),
    ("ph.d.", DEGREE_PHD),
    ("phd", DEGREE_PHD),
    ("doctorate", DEGREE_PHD),
    ("doctoral", DEGREE_PHD),
    ("doctor of philosophy", DEGREE_PHD),

    # Masters
    ("master's", DEGREE_MASTERS),
    ("masters", DEGREE_MASTERS),
    ("master of science", DEGREE_MASTERS),
    ("master of arts", DEGREE_MASTERS),
    ("master of business", DEGREE_MASTERS),
    ("master of eng", DEGREE_MASTERS),
    ("master", DEGREE_MASTERS),
    ("msc", DEGREE_MASTERS),
    ("m.sc", DEGREE_MASTERS),
    ("m.sc.", DEGREE_MASTERS),
    ("ms", DEGREE_MASTERS),
    ("ma", DEGREE_MASTERS),
    ("mba", DEGREE_MASTERS),
    ("meng", DEGREE_MASTERS),
    ("m.eng", DEGREE_MASTERS),

    # Bachelors
    ("bachelor's", DEGREE_BACHELORS),
    ("bachelors", DEGREE_BACHELORS),
    ("bachelor of science", DEGREE_BACHELORS),
    ("bachelor of arts", DEGREE_BACHELORS),
    ("bachelor of eng", DEGREE_BACHELORS),
    ("bachelor", DEGREE_BACHELORS),
    ("bsc", DEGREE_BACHELORS),
    ("b.sc", DEGREE_BACHELORS),
    ("b.sc.", DEGREE_BACHELORS),
    ("bs", DEGREE_BACHELORS),
    ("ba", DEGREE_BACHELORS),
    ("beng", DEGREE_BACHELORS),
    ("b.eng", DEGREE_BACHELORS),
    ("undergraduate", DEGREE_BACHELORS),
    ("undergraduates", DEGREE_BACHELORS),
)


def normalize_degree(value: Optional[str]) -> Optional[str]:
    """Return the canonical degree token for ``value``.

    The function picks the first matching rule from ``_DEGREE_RULES``
    (longest / most specific first). When ``value`` is a comma-joined
    list ("Bachelor, Master"), the first recognisable token is
    returned.

    Args:
        value: Raw degree string from an upstream source.

    Returns:
        One of ``"Bachelors"``, ``"Masters"``, ``"PhD"``,
        ``"PostDoc"``, or ``None`` when no token matches.
    """
    if value is None:
        return None
    cleaned = clean_text(value)
    if not cleaned:
        return None
    haystack = cleaned.lower()
    for needle, canonical in _DEGREE_RULES:
        if needle in haystack:
            return canonical
    return None


# ---------------------------------------------------------------------------
# Funding normalisation
# ---------------------------------------------------------------------------

FUNDING_FULLY_FUNDED: str = "Fully Funded"
FUNDING_PARTIALLY_FUNDED: str = "Partially Funded"
FUNDING_SELF_FUNDED: str = "Self Funded"
FUNDING_UNKNOWN: str = "Unknown"

_FUNDING_FULLY_TOKENS: frozenset[str] = frozenset({
    "fully funded",
    "full funding",
    "100% funded",
    "100% funding",
    "100 percent funded",
    "fully financed",
    "full scholarship",
    "complete funding",
    "all expenses covered",
    "fully-covered",
})

_FUNDING_PARTIAL_TOKENS: frozenset[str] = frozenset({
    "partial funding",
    "partially funded",
    "partial scholarship",
    "partially financed",
    "partial",
    "some funding",
    "co-funded",
    "cofunded",
})

_FUNDING_SELF_TOKENS: frozenset[str] = frozenset({
    "self funded",
    "self-funded",
    "no funding",
    "unfunded",
    "self financed",
})


def normalize_funding(value: Optional[str]) -> str:
    """Return the canonical funding label for ``value``.

    The mapping is:

    * "Fully funded" family → :data:`FUNDING_FULLY_FUNDED`
    * "Partial funding" family → :data:`FUNDING_PARTIALLY_FUNDED`
    * "Self funded" family → :data:`FUNDING_SELF_FUNDED`
    * Anything else (including ``None`` / empty) → :data:`FUNDING_UNKNOWN`

    Args:
        value: Raw funding string from an upstream source.

    Returns:
        A canonical funding label.
    """
    if value is None:
        return FUNDING_UNKNOWN
    cleaned = clean_text(value).lower()
    if not cleaned:
        return FUNDING_UNKNOWN
    if cleaned in _FUNDING_FULLY_TOKENS:
        return FUNDING_FULLY_FUNDED
    if cleaned in _FUNDING_PARTIAL_TOKENS:
        return FUNDING_PARTIALLY_FUNDED
    if cleaned in _FUNDING_SELF_TOKENS:
        return FUNDING_SELF_FUNDED
    if "fully" in cleaned or "100%" in cleaned:
        return FUNDING_FULLY_FUNDED
    if "partial" in cleaned:
        return FUNDING_PARTIALLY_FUNDED
    if "self" in cleaned or "no funding" in cleaned:
        return FUNDING_SELF_FUNDED
    return FUNDING_UNKNOWN


# ---------------------------------------------------------------------------
# Deadline normalisation
# ---------------------------------------------------------------------------

#: Tokens that mean "no specific deadline" — always become ``None``.
DEADLINE_NONE_TOKENS: frozenset[str] = frozenset({
    "see official page",
    "see official website",
    "see official",
    "see website",
    "rolling",
    "open",
    "tba",
    "to be announced",
    "to be determined",
    "tbd",
    "unknown",
    "n/a",
    "na",
    "none",
    "-",
    "—",
    "–",
})

#: Final canonical date format produced by :func:`normalize_deadline`.
DEADLINE_FORMAT: str = "%Y-%m-%d"


def normalize_deadline(value: Optional[str]) -> Optional[str]:
    """Return the deadline as ``YYYY-MM-DD`` or ``None``.

    The function first checks :data:`DEADLINE_NONE_TOKENS` for the
    well-known "no specific date" phrasings. Otherwise it delegates to
    :func:`dateutil.parser.parse` with ``dayfirst=True`` and
    ``fuzzy=False`` so it never guesses.

    Args:
        value: Raw deadline string from an upstream source.

    Returns:
        ISO-8601 ``YYYY-MM-DD`` string, or ``None`` when the value is
        empty, a "no specific date" token, or unparseable.
    """
    if value is None:
        return None
    cleaned = clean_text(value)
    if not cleaned:
        return None
    if cleaned.lower() in DEADLINE_NONE_TOKENS:
        return None
    try:
        parsed = _date_parser.parse(cleaned, fuzzy=False, dayfirst=True)
    except (ValueError, TypeError, OverflowError):
        _logger.debug("Could not parse deadline: %r", value)
        return None
    try:
        return parsed.strftime(DEADLINE_FORMAT)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Free-text cleaning
# ---------------------------------------------------------------------------

_HTML_ENTITY_RE = re.compile(r"&[a-zA-Z]+;|&#\d+;")
_MULTI_WHITESPACE_RE = re.compile(r"\s+")
_MULTI_PUNCT_RE = re.compile(r"([.,;:!?])\1+")
_MULTI_DASH_RE = re.compile(r"-{2,}")
_CGPA_RE = re.compile(r"(?:minimum\s+)?cgpa\s*(?:of|:|=|is)?\s*(\d(?:\.\d+)?)", re.I)
_IELTS_RE = re.compile(r"\bielts\b", re.I)
_RESEARCH_RE = re.compile(r"\b(research|thesis|doctoral|phd|postdoctoral)\b", re.I)



def clean_text(value: Optional[str]) -> str:
    """Return ``value`` with whitespace, HTML entities, and repeated
    punctuation collapsed.

    The transformation is intentionally conservative:

    * HTML entities (``&amp;``, ``&#10;``) are removed.
    * Multiple whitespace characters collapse to a single space.
    * ``.``, ``,``, ``;``, ``:``, ``!``, ``?`` repeated 2+ times
      collapse to a single instance.
    * Runs of ``-`` collapse to a single ``-``.
    * All leading/trailing whitespace is stripped.

    Args:
        value: Raw text from an upstream source.

    Returns:
        Cleaned text. Empty string when ``value`` is ``None``.
    """
    if value is None:
        return ""
    text = str(value)
    text = _HTML_ENTITY_RE.sub(" ", text)
    text = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
    text = text.replace("\t", " ")
    text = _MULTI_WHITESPACE_RE.sub(" ", text)
    text = _MULTI_PUNCT_RE.sub(r"\1", text)
    text = _MULTI_DASH_RE.sub("-", text)
    return text.strip()


def _number(value: Any, default: float) -> float:
    """Return a non-negative numeric criterion with a safe default."""
    try:
        return max(0.0, float(value))
    except (TypeError, ValueError):
        return default


def _infer_min_cgpa(record: Dict[str, Any], text: str) -> float:
    explicit = record.get("min_cgpa", record.get("minCgpa"))
    if explicit is not None and str(explicit).strip() != "":
        return _number(explicit, 0.0)
    match = _CGPA_RE.search(text)
    return float(match.group(1)) if match else 0.0


# ---------------------------------------------------------------------------
# Package-level entry point
# ---------------------------------------------------------------------------

#: Fields that should be cleaned but not transformed.
_TEXT_FIELDS: tuple[str, ...] = (
    "title",
    "description",
    "eligibility",
    "university",
    "tags",
)


def normalize_scholarship(record: Dict[str, Any]) -> Dict[str, Any]:
    """Return a normalised copy of ``record``.

    The function applies every transformation in this module in a
    single pass and returns a **new** dict — the input is never
    mutated.

    Field-level rules:

    * ``country`` → :func:`normalize_country`
    * ``degree`` → :func:`normalize_degree`
    * ``funding_type`` / ``amount`` → :func:`normalize_funding`
    * ``deadline`` → :func:`normalize_deadline`
    * ``title`` / ``description`` / ``eligibility`` / ``university`` →
      :func:`clean_text`
    * ``tags`` → list of cleaned strings (empty list when missing)
    * everything else is shallow-copied

    Args:
        record: Raw record produced by a scraper.

    Returns:
        A new dict with normalised values.
    """
    _logger.debug("normalize_scholarship: %s", record.get("title") or record.get("official_id"))
    out: Dict[str, Any] = {}

    # Country
    out["country"] = normalize_country(record.get("country"))

    # Degree
    out["degree"] = normalize_degree(record.get("degree"))

    # Funding — honour ``funding_type`` first, fall back to ``amount``.
    funding_raw = record.get("funding_type") or record.get("amount")
    out["funding_type"] = normalize_funding(funding_raw)
    out["amount"] = out["funding_type"]

    # Deadline
    out["deadline"] = normalize_deadline(record.get("deadline"))

    # Free-text fields
    for field_name in _TEXT_FIELDS:
        if field_name == "tags":
            continue
        out[field_name] = clean_text(record.get(field_name))

    # Tags — must be a list of cleaned strings.
    raw_tags = record.get("tags") or []
    if isinstance(raw_tags, str):
        raw_tags = [t for t in re.split(r"[,;|]", raw_tags) if t.strip()]
    out["tags"] = [clean_text(t) for t in raw_tags if clean_text(t)]

    # Criteria remain absent until an official source states them. The
    # enrichment stage populates these values before this normalizer runs.
    source_text = " ".join(
        clean_text(record.get(key))
        for key in ("title", "description", "eligibility", "field")
    )
    out["image"] = clean_text(record.get("image")) or None
    out["link"] = clean_text(record.get("link")) or clean_text(record.get("apply_url"))
    out["apply_url"] = clean_text(record.get("apply_url")) or out["link"]
    out["eligibility"] = out["eligibility"] or None
    out["description"] = out["description"] or None
    out["university"] = out["university"] or None
    out["category"] = clean_text(record.get("category")) or (
        out["tags"][0] if out["tags"] else None
    )
    out["fully_funded"] = out["funding_type"] == FUNDING_FULLY_FUNDED
    out["min_cgpa"] = _infer_min_cgpa(record, source_text)
    out["cgpa_scale"] = _number(
        record.get("cgpa_scale", record.get("cgpaScale", 4)), 4.0
    ) or 4.0
    out["max_backlogs"] = int(_number(
        record.get("max_backlogs", record.get("maxBacklogs", 0)), 0.0
    ))
    out["english_medium_accepted"] = record.get(
        "english_medium_accepted", record.get("englishMediumAccepted")
    )
    out["ielts_required"] = bool(record.get("ielts_required", False)) or bool(
        _IELTS_RE.search(source_text)
    )
    out["research_required"] = bool(record.get("research_required", False)) or bool(
        _RESEARCH_RE.search(source_text)
    )

    # Copy the remaining fields unchanged.
    for key, value in record.items():
        if key in out:
            continue
        out[key] = value

    # Drop empty title / country after normalisation so validators
    # can flag them as Invalid.
    if not out.get("title"):
        out["title"] = ""
    return out
