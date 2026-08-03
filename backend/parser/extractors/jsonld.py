"""JSON-LD / Schema.org structured data extraction.

Pages that embed ``<script type="application/ld+json">`` provide the
highest-quality extraction source available — structured data is
authored by the publisher, not inferred from HTML. We therefore read
JSON-LD before OpenGraph/Twitter/HTML meta tags in the engine's
priority order.

The module handles every common JSON-LD layout:

* Single object: ``{"@type": "Scholarship", ...}``
* ``@graph`` arrays: ``{"@graph": [ {...}, {...} ]}``
* ``@list``: ``{"@list": [ {...} ]}``
* ``@nest``: ``{"@nest": { "@type": ... }}``
* ``@set`` / nested arrays: recursively walked.

We never invent fields. If a structured-data block lacks a value, we
return ``None`` and let downstream extractors fall through to the next
priority.

The :class:`JsonLdNode` dataclass normalises every shape into a single
instance, with optional fields for the slots the rest of the engine
asks about. The :class:`JsonLdDocument` aggregates every node found in
the page.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional, Sequence

from bs4 import BeautifulSoup

from .html import strip_noise

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

#: ``@type`` values that we interpret as scholarship-like entities.
SCHOLARSHIP_TYPES: frozenset[str] = frozenset(
    {
        "Scholarship",
        "EducationalOccupationalProgram",
        "EducationalOccupationalCredential",
        "Program",
        "Course",
        "FundingScheme",
        "Grant",
        "GovernmentService",
        "FinancialProduct",
        "Service",  # Some scholarship pages are typed as Service.
    }
)

#: ``@type`` values mapped to "provider / organization".
ORGANIZATION_TYPES: frozenset[str] = frozenset(
    {
        "Organization",
        "EducationalOrganization",
        "CollegeOrUniversity",
        "University",
        "College",
        "GovernmentOrganization",
        "NGO",
        "AdministrativeArea",
        "Country",
    }
)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class JsonLdNode:
    """One parsed JSON-LD entity."""

    type: Optional[str] = None
    name: Optional[str] = None
    description: Optional[str] = None
    url: Optional[str] = None
    image: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    deadline: Optional[str] = None
    provider_name: Optional[str] = None
    provider_url: Optional[str] = None
    organization_name: Optional[str] = None
    organization_url: Optional[str] = None
    funding: Dict[str, Any] = field(default_factory=dict)
    eligibility: List[str] = field(default_factory=list)
    location: Optional[str] = None
    salary_currency: Optional[str] = None
    salary_value: Optional[Any] = None
    raw: Dict[str, Any] = field(default_factory=dict)

    @property
    def is_scholarship(self) -> bool:
        """Return ``True`` when the node type looks like a scholarship."""
        if not self.type:
            return False
        return self.type in SCHOLARSHIP_TYPES


@dataclass
class JsonLdDocument:
    """All structured-data nodes parsed from a single page."""

    nodes: List[JsonLdNode] = field(default_factory=list)
    raw_blocks: List[Dict[str, Any]] = field(default_factory=list)
    parse_errors: List[str] = field(default_factory=list)

    def first_scholarship(self) -> Optional[JsonLdNode]:
        """Return the first scholarship-like node, or ``None``."""
        for node in self.nodes:
            if node.is_scholarship:
                return node
        return None

    def first_organization(self) -> Optional[JsonLdNode]:
        """Return the first organization-like node, or ``None``."""
        for node in self.nodes:
            if node.type in ORGANIZATION_TYPES:
                return node
        return None


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def _iter_strings(node: Any) -> Iterable[str]:
    """Yield every string value inside a nested JSON structure."""
    if isinstance(node, dict):
        for value in node.values():
            yield from _iter_strings(value)
    elif isinstance(node, list):
        for item in node:
            yield from _iter_strings(item)
    elif isinstance(node, str):
        yield node


def _coerce_type(value: Any) -> Optional[str]:
    """Return the @type as a string (handle list-typed values)."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        for item in value:
            text = _coerce_type(item)
            if text:
                return text
    return None


def _coerce_text(value: Any) -> Optional[str]:
    """Return ``value`` as a clean string, or ``None``."""
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, dict):
        # Some publishers encode text as ``{"@value": "..."}`` in non-RDFA
        # blocks too.
        for key in ("@value", "value", "text"):
            if key in value:
                return _coerce_text(value[key])
    if isinstance(value, list):
        for item in value:
            text = _coerce_text(item)
            if text:
                return text
    return None


def _coerce_image(value: Any) -> Optional[str]:
    """Return the URL of a Schema-org ``image`` field."""
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, dict):
        for key in ("url", "@id", "contentUrl"):
            if key in value:
                url = _coerce_image(value[key])
                if url:
                    return url
    if isinstance(value, list):
        for item in value:
            url = _coerce_image(item)
            if url:
                return url
    return None


def _coerce_organization(value: Any) -> tuple[Optional[str], Optional[str]]:
    """Return ``(name, url)`` extracted from an Organization-shaped value."""
    if value is None:
        return None, None
    if isinstance(value, str):
        return value, None
    if isinstance(value, dict):
        name = _coerce_text(value.get("name"))
        url = _coerce_text(value.get("url"))
        if name is None and isinstance(value.get("provider"), dict):
            nested = value["provider"]
            return _coerce_organization(nested)
        return name, url
    if isinstance(value, list):
        for item in value:
            name, url = _coerce_organization(item)
            if name or url:
                return name, url
    return None, None


def _coerce_eligibility(value: Any) -> List[str]:
    """Return a list of eligibility strings."""
    if value is None:
        return []
    items: List[str] = []
    if isinstance(value, str):
        if value.strip():
            items.append(value.strip())
    elif isinstance(value, dict):
        text = _coerce_text(value.get("text"))
        if text:
            items.append(text)
    elif isinstance(value, list):
        for item in value:
            items.extend(_coerce_eligibility(item))
    return items


def _coerce_money(value: Any) -> tuple[Optional[Any], Optional[str]]:
    """Return ``(value, currency)`` from a ``MonetaryAmount`` block."""
    if value is None:
        return None, None
    if isinstance(value, str):
        return value, None
    if isinstance(value, (int, float)):
        return value, None
    if isinstance(value, dict):
        currency = _coerce_text(
            value.get("currency") or value.get("priceCurrency")
        )
        raw_value = (
            value.get("value")
            or value.get("amount")
            or value.get("price")
        )
        amount = None
        if isinstance(raw_value, (int, float)):
            amount = raw_value
        elif isinstance(raw_value, str):
            amount = re.findall(r"[\d,.\s]+", raw_value)
            amount = amount[0].strip() if amount else raw_value.strip()
        return amount, currency
    if isinstance(value, list):
        for item in value:
            amount, currency = _coerce_money(item)
            if amount is not None or currency is not None:
                return amount, currency
    return None, None


def parse_node(data: Dict[str, Any]) -> JsonLdNode:
    """Build a :class:`JsonLdNode` from a parsed JSON-LD dictionary."""
    node = JsonLdNode()
    node.raw = dict(data)
    node.type = _coerce_type(data.get("@type"))
    node.name = _coerce_text(data.get("name"))
    node.description = _coerce_text(data.get("description"))
    node.url = _coerce_text(data.get("url"))
    node.image = _coerce_image(data.get("image"))
    node.start_date = _coerce_text(data.get("startDate"))
    node.end_date = _coerce_text(data.get("endDate"))
    node.deadline = _coerce_text(data.get("applicationDeadline"))
    if not node.deadline:
        node.deadline = _coerce_text(data.get("deadline"))

    provider_name, provider_url = _coerce_organization(data.get("provider"))
    node.provider_name = provider_name
    node.provider_url = provider_url

    if not node.organization_name:
        org_name, org_url = _coerce_organization(
            data.get("organization") or data.get("provider")
        )
        node.organization_name = org_name
        node.organization_url = org_url
    else:
        node.organization_url = provider_url

    eligibility = data.get("eligible") or data.get("eligibility")
    node.eligibility = _coerce_eligibility(eligibility)

    amount, currency = _coerce_money(data.get("salary") or data.get("amount"))
    if amount is not None or currency is not None:
        node.funding["amount"] = amount
        node.funding["currency"] = currency
        node.salary_currency = currency
        node.salary_value = amount

    address = data.get("address")
    if isinstance(address, dict):
        locality = _coerce_text(address.get("addressLocality"))
        country = _coerce_text(address.get("addressCountry"))
        if locality and country:
            node.location = f"{locality}, {country}"
        elif country or locality:
            node.location = country or locality
    return node


def _flatten(data: Any, output: List[Dict[str, Any]]) -> None:
    """Walk ``data`` and append every ``@type``-bearing dict to ``output``."""
    if isinstance(data, dict):
        if "@type" in data and not isinstance(data.get("@type"), list):
            output.append(data)
        for value in data.values():
            _flatten(value, output)
    elif isinstance(data, list):
        for item in data:
            _flatten(item, output)


def parse_blocks(blocks: Sequence[Any]) -> JsonLdDocument:
    """Convert parsed JSON-LD blocks (already decoded as Python) into a document."""
    document = JsonLdDocument()
    flat: List[Dict[str, Any]] = []
    for block in blocks:
        if isinstance(block, dict):
            document.raw_blocks.append(block)
            _flatten(block, flat)
        elif isinstance(block, list):
            for inner in block:
                if isinstance(inner, dict):
                    document.raw_blocks.append(inner)
                    _flatten(inner, flat)
    for raw in flat:
        try:
            document.nodes.append(parse_node(raw))
        except Exception as exc:  # pragma: no cover - defensive
            document.parse_errors.append(str(exc))
            logger.debug("Failed to parse JSON-LD node: %s", exc)
    return document


def extract_jsonld(soup: BeautifulSoup) -> JsonLdDocument:
    """Return every JSON-LD node on the page.

    The function:

    * removes navigation/script chrome via :func:`html.strip_noise`,
    * extracts every ``<script type="application/ld+json">`` body,
    * decodes JSON defensively (silently logs malformed blocks),
    * flattens ``@graph`` / ``@list`` containers, and
    * maps each ``@type``-bearing record to a :class:`JsonLdNode`.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        A :class:`JsonLdDocument` containing every parsed node plus the
        raw blocks (useful for testing) and any decoder errors.
    """
    document = JsonLdDocument()
    if soup is None:
        return document

    cleaned = strip_noise(soup)
    scripts = cleaned.find_all(
        "script",
        attrs={"type": re.compile(r"ld\+json", re.I)},
    )
    for script in scripts:
        text = script.get_text()
        if not text or not text.strip():
            continue
        # JSON-LD is rarely HTML-encoded but be defensive.
        unescaped = (
            text.replace("&quot;", '"')
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
        )
        try:
            data = json.loads(unescaped)
        except json.JSONDecodeError as exc:
            document.parse_errors.append(str(exc))
            logger.debug("Skipping malformed JSON-LD block: %s", exc)
            continue
        try:
            fragment = parse_blocks([data])
        except Exception as exc:  # pragma: no cover - defensive
            document.parse_errors.append(str(exc))
            continue
        document.nodes.extend(fragment.nodes)
        document.raw_blocks.extend(fragment.raw_blocks)
        document.parse_errors.extend(fragment.parse_errors)

    # Deduplicate by (type, name, url) triple.
    seen: set[tuple[Optional[str], Optional[str], Optional[str]]] = set()
    unique: List[JsonLdNode] = []
    for node in document.nodes:
        key = (node.type, node.name, node.url)
        if key in seen:
            continue
        seen.add(key)
        unique.append(node)
    document.nodes = unique

    return document


__all__ = [
    "JsonLdDocument",
    "JsonLdNode",
    "SCHOLARSHIP_TYPES",
    "ORGANIZATION_TYPES",
    "extract_jsonld",
    "parse_blocks",
    "parse_node",
]
