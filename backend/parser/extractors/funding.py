"""Funding / benefits extraction.

Pages describe scholarships using one of three patterns:

1. A summary line: "Fully Funded" / "Partially Funded".
2. A bullet list of benefits (tuition, stipend, accommodation…).
3. A prose paragraph that mentions amounts and currencies.

We expose a single :func:`extract_funding` that walks a soup tree,
classifies every benefit flag independently, and assembles a
:class:`Funding` dataclass.

Crucially, we **never invent amounts**. A page that simply says
"Fully Funded" yields ``fullyFunded=True`` but ``amount=None``;
a page that says "₹50,000/month" yields ``monthlyStipend=50000.0``,
``currency="INR"``, and ``benefits=["Monthly Stipend"]`` — but no
``amount`` field.

Slots exposed (mirroring the canonical Flutter map):

* ``funding`` — string: ``"Fully Funded"`` / ``"Partially Funded"`` / ``Self Funded``.
* ``fullyFunded`` — bool.
* ``amount`` — optional float (``None`` when not stated).
* ``currency`` — optional str.
* ``monthlyStipend`` — optional float (``None`` when not stated).
* ``benefits`` — list of normalised benefit labels.
* ``notes`` — raw extracted evidence lines.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence

from bs4 import BeautifulSoup

from .html import extract_text, find_section, strip_noise


# ---------------------------------------------------------------------------
# Canonical benefit labels
# ---------------------------------------------------------------------------

#: Canonical labels produced by this module. These stay in sync with
#: the Flutter app's options list (``add_scholarship_page.dart``).
BENEFIT_TUITION: str = "Tuition Fee"
BENEFIT_TUITION_WAIVER: str = "Tuition Waiver"
BENEFIT_MONTHLY: str = "Monthly Stipend"
BENEFIT_ACCOMMODATION: str = "Accommodation"
BENEFIT_FLIGHT: str = "Travel Grant"
BENEFIT_INSURANCE: str = "Health Insurance"
BENEFIT_RESEARCH_GRANT: str = "Research Grant"
BENEFIT_EMERGENCY: str = "Emergency Grant"
BENEFIT_BOOK_ALLOWANCE: str = "Book Allowance"
BENEFIT_SETTLEMENT: str = "Settlement Allowance"

ALL_BENEFITS: tuple[str, ...] = (
    BENEFIT_TUITION,
    BENEFIT_TUITION_WAIVER,
    BENEFIT_MONTHLY,
    BENEFIT_ACCOMMODATION,
    BENEFIT_FLIGHT,
    BENEFIT_INSURANCE,
    BENEFIT_RESEARCH_GRANT,
    BENEFIT_EMERGENCY,
    BENEFIT_BOOK_ALLOWANCE,
    BENEFIT_SETTLEMENT,
)


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------


@dataclass
class Funding:
    """All funding information extracted from a single page."""

    funding: Optional[str] = None
    fullyFunded: bool = False
    partiallyFunded: bool = False
    amount: Optional[float] = None
    currency: Optional[str] = None
    monthlyStipend: Optional[float] = None
    stipend_currency: Optional[str] = None
    annual_value: Optional[float] = None
    benefits: List[str] = field(default_factory=list)
    notes: List[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Regex catalog
# ---------------------------------------------------------------------------

_FULLY_FUNDED_RE = re.compile(
    r"\bfully\s+funded\b|\bfully-funded\b|\b100\s*%\s*funded\b",
    re.I,
)

_PARTIAL_RE = re.compile(
    r"\b(?:partial(?:ly)?[-\s]?funded|partially[- ]funded"
    r"|partial\s+scholarship|partial[- ]scholarship)\b",
    re.I,
)

_SELF_FUNDED_RE = re.compile(
    r"\b(?:self[-\s]?funded|self[-\s]?financed|self[-\s]?sponsored"
    r"|no\s+funding\s+provided)\b",
    re.I,
)

_TUITION_FEE_RE = re.compile(
    r"\b(?:tuition\s+(?:fee|fee\s+waiver|fee\s+covered"
    r"|fee\s+is\s+covered|fees?\s+are\s+covered"
    r"|fees?\s+will\s+be\s+(?:covered|paid|waived)))\b",
    re.I,
)

_TUITION_WAIVER_RE = re.compile(
    r"\b(?:tuition\s+waiver|waiver\s+of\s+tuition"
    r"|tuition[- ]fee\s+waiver|tuition[- ]fee[- ]exemption)\b",
    re.I,
)

_MONTHLY_RE = re.compile(
    r"\b(?:monthly\s+stipend|stipend\s+of|monthly\s+(?:allowance|grant)"
    r"|(?:Rs\.?|₹|USD\s*\$|US\$|£|€|A\$|AU\$|C\$|CA\$|\$)\s*"
    r"(?P<amount>[\d,]+(?:\.\d+)?)\s*(?:/|per|\s+per\s+)?\s*(?:month|monthly|/\s*month)\b)",
    re.I,
)

_ACCOMMODATION_RE = re.compile(
    r"\b(?:accommodation|hostel\s+(?:allowance|fees?|is\s+provided)"
    r"|housing\s+(?:allowance|is\s+provided)\s+is\s+provided"
    r"|on[- ]campus\s+housing|living\s+allowance|living\s+expenses?)\b",
    re.I,
)

_FLIGHT_RE = re.compile(
    r"\b(?:air\s*ticket|air\s*fare|flight\s+ticket|travel\s+(?:grant|allowance"
    r"|cost|expense|reimbursement)|airfare\s+reimbursement)\b",
    re.I,
)

_INSURANCE_RE = re.compile(
    r"\b(?:health\s+insurance|medical\s+insurance|insurance\s+coverage)\b",
    re.I,
)

_RESEARCH_GRANT_RE = re.compile(
    r"\b(?:research\s+(?:grant|funding|allowance|support))\b",
    re.I,
)

_EMERGENCY_RE = re.compile(
    r"\b(?:emergency\s+(?:grant|funding|support|loan))\b",
    re.I,
)

_BOOK_RE = re.compile(
    r"\b(?:book\s+allowance|books?\s+allowance|textbook\s+allowance)\b",
    re.I,
)

_SETTLEMENT_RE = re.compile(
    r"\b(?:settlement\s+allowance|relocation\s+(?:allowance|grant|support))\b",
    re.I,
)

_TOTAL_AMOUNT_RE = re.compile(
    r"\b(?:total\s+(?:worth|value|amount|funding|cover))\s*"
    r"(?:of|:)?\s*"
    r"(?P<amount>\$|USD|Rs\.?|₹|£|€|A\$|AU\$|C\$|CA\$)?\s*"
    r"(?P<value>[\d,]+(?:\.\d+)?)\s*(?P<unit>USD|EUR|GBP|AUD|CAD|INR|€|\$|£)?",
    re.I,
)

_CURRENCY_RE = re.compile(
    r"\b(?P<symbol>[$€£¥₹]|USD|EUR|GBP|INR|PKR|AUD|CAD|JPY|CNY|RMB|Rs\.?)\b",
    re.I,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _parse_amount(text: str, amount: str) -> Optional[float]:
    """Parse a numeric amount string into a float, ignoring thousands sep."""
    if not amount:
        return None
    cleaned = amount.replace(",", "").replace(" ", "")
    try:
        return float(cleaned)
    except ValueError:
        return None


def _resolve_currency(text: str) -> Optional[str]:
    """Pick the first currency symbol/code in ``text``."""
    if not text:
        return None
    match = _CURRENCY_RE.search(text)
    if not match:
        return None
    symbol = match.group("symbol").upper().replace(".", "")
    aliases = {
        "$": "USD",
        "£": "GBP",
        "€": "EUR",
        "¥": "JPY",
        "₹": "INR",
        "RS": "INR",
        "USD": "USD",
        "EUR": "EUR",
        "GBP": "GBP",
        "INR": "INR",
        "PKR": "PKR",
        "AUD": "AUD",
        "CAD": "CAD",
        "JPY": "JPY",
        "CNY": "CNY",
        "RMB": "CNY",
    }
    return aliases.get(symbol, symbol)


# ---------------------------------------------------------------------------
# Section heading candidates
# ---------------------------------------------------------------------------

_HEADINGS: tuple[str, ...] = (
    "Benefits",
    "Scholarship Benefits",
    "What is Covered",
    "What's Covered",
    "Funding",
    "Financial Support",
    "Coverage",
    "Award",
    "Award Details",
    "Value",
    "Value of Award",
    "Scholarship Coverage",
)

_STOP_HEADINGS: tuple[str, ...] = (
    "Eligibility",
    "Application Procedure",
    "How to Apply",
    "Required Documents",
    "Deadlines",
    "Application Deadline",
    "Contact",
    "Frequently Asked Questions",
    "FAQs",
    "FAQ",
)


# ---------------------------------------------------------------------------
# Internal extractors
# ---------------------------------------------------------------------------


def _sections_text(soup: BeautifulSoup) -> str:
    fragment = find_section(
        soup, list(_HEADINGS), stop_headings=list(_STOP_HEADINGS)
    )
    if fragment is None:
        return ""
    return extract_text(fragment)


def _has_match(text: str, pattern: re.Pattern) -> bool:
    return bool(pattern.search(text))


def _match_list(text: str, pattern: re.Pattern) -> List[str]:
    return [m.group(0).strip() for m in pattern.finditer(text)]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def extract_funding(soup: BeautifulSoup) -> Funding:
    """Return funding flags parsed from ``soup``.

    The function is read-only on the input tree and never raises; on
    malformed HTML it returns the partial information it could find.

    Args:
        soup: Source :class:`BeautifulSoup`.

    Returns:
        Populated :class:`Funding`.
    """
    result = Funding()
    if soup is None:
        return result

    cleaned = strip_noise(soup)
    page_text = extract_text(cleaned)
    if not page_text:
        return result

    section_text = _sections_text(cleaned)
    haystack = section_text if section_text else page_text

    # 1. Coverage type — fully / partial / self.
    if _has_match(haystack, _FULLY_FUNDED_RE):
        result.fullyFunded = True
        result.funding = "Fully Funded"
    if _has_match(haystack, _PARTIAL_RE):
        result.partiallyFunded = True
        if not result.fullyFunded:
            result.funding = "Partially Funded"
    if _has_match(haystack, _SELF_FUNDED_RE):
        if not result.fullyFunded and not result.partiallyFunded:
            result.funding = "Self Funded"

    # 2. Tuition coverage.
    has_tuition = bool(
        _TUITION_FEE_RE.search(haystack) or _TUITION_WAIVER_RE.search(haystack)
    )
    if has_tuition:
        result.benefits.append(BENEFIT_TUITION_WAIVER)
        result.benefits.append(BENEFIT_TUITION)
        result.notes.extend(
            _match_list(haystack, _TUITION_FEE_RE)
            + _match_list(haystack, _TUITION_WAIVER_RE)
        )

    # 3. Monthly stipend.
    for match in _MONTHLY_RE.finditer(haystack):
        amount = _parse_amount(match.group("amount"), match.group("amount"))
        if amount is not None:
            result.monthlyStipend = amount
            result.stipend_currency = _resolve_currency(match.group(0))
            result.benefits.append(BENEFIT_MONTHLY)
            result.notes.append(match.group(0).strip())
            break  # first hit wins

    # 4. Travel grant.
    travel_matches = _match_list(haystack, _FLIGHT_RE)
    if travel_matches:
        result.benefits.append(BENEFIT_FLIGHT)
        result.notes.extend(travel_matches)

    # 5. Accommodation.
    accommodation_matches = _match_list(haystack, _ACCOMMODATION_RE)
    if accommodation_matches:
        result.benefits.append(BENEFIT_ACCOMMODATION)
        result.notes.extend(accommodation_matches)

    # 6. Insurance.
    insurance_matches = _match_list(haystack, _INSURANCE_RE)
    if insurance_matches:
        result.benefits.append(BENEFIT_INSURANCE)
        result.notes.extend(insurance_matches)

    # 7. Research grant.
    research_matches = _match_list(haystack, _RESEARCH_GRANT_RE)
    if research_matches:
        result.benefits.append(BENEFIT_RESEARCH_GRANT)
        result.notes.extend(research_matches)

    # 8. Emergency grant.
    if _has_match(haystack, _EMERGENCY_RE):
        result.benefits.append(BENEFIT_EMERGENCY)
        result.notes.extend(_match_list(haystack, _EMERGENCY_RE))

    # 9. Book allowance.
    if _has_match(haystack, _BOOK_RE):
        result.benefits.append(BENEFIT_BOOK_ALLOWANCE)
        result.notes.extend(_match_list(haystack, _BOOK_RE))

    # 10. Settlement allowance.
    if _has_match(haystack, _SETTLEMENT_RE):
        result.benefits.append(BENEFIT_SETTLEMENT)
        result.notes.extend(_match_list(haystack, _SETTLEMENT_RE))

    # 11. Total value (only if explicitly stated).
    total_match = _TOTAL_AMOUNT_RE.search(haystack)
    if total_match is not None:
        amount = _parse_amount(
            total_match.group("value"), total_match.group("value")
        )
        if amount is not None:
            result.annual_value = amount
            result.notes.append(total_match.group(0).strip())

    # 12. Currency fallback (from any detected amount or symbol).
    if result.stipend_currency and not result.currency:
        result.currency = result.stipend_currency
    elif result.annual_value and not result.currency:
        result.currency = _resolve_currency(haystack)

    # Final ordering — keep the benefit list canonical and unique.
    result.benefits = _ordered_unique(result.benefits)
    result.notes = _ordered_unique(result.notes)
    return result


def _ordered_unique(items: Sequence[str]) -> List[str]:
    seen: set[str] = set()
    ordered: List[str] = []
    for item in items:
        key = item.strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        ordered.append(item.strip())
    return ordered


__all__ = [
    "Funding",
    "BENEFIT_TUITION",
    "BENEFIT_TUITION_WAIVER",
    "BENEFIT_MONTHLY",
    "BENEFIT_ACCOMMODATION",
    "BENEFIT_FLIGHT",
    "BENEFIT_INSURANCE",
    "BENEFIT_RESEARCH_GRANT",
    "BENEFIT_EMERGENCY",
    "BENEFIT_BOOK_ALLOWANCE",
    "BENEFIT_SETTLEMENT",
    "ALL_BENEFITS",
    "extract_funding",
]
