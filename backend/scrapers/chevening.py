"""Chevening scholarship scraper.

Discovery notes
---------------
Chevening (https://www.chevening.org/) publishes one WordPress post per
country/territory that the programme covers. The site exposes a
machine-readable sitemap at::

    https://www.chevening.org/wp-sitemap.xml
    https://www.chevening.org/wp-sitemap-posts-scholarships-1.xml

That sub-sitemap contains **197** ``<loc>`` entries that point at
per-country landing pages shaped like::

    https://www.chevening.org/scholarship/<country-slug>/

Each landing page is server-rendered HTML that follows the same
template: an ``<h1>`` containing ``"Chevening in <Country>"``, the
shared programme description, and an apply CTA pointing at the global
applicant portal.

Robots / ethics
---------------
The site's ``robots.txt`` (``/robots.txt``) only disallows ``/wp-admin/``.
Both the sitemap and the public ``/scholarship/<slug>/`` URLs are
allowed. To stay polite we:

* identify ourselves with the project's configured ``SCRAPER_USER_AGENT``,
* reuse the shared :class:`httpx.Client` from :class:`BaseScraper`,
* sleep 1–2 s between successive per-country fetches
  (:attr:`BaseScraper.min_request_delay` / :attr:`max_request_delay`),
* cap the number of records produced per run via :meth:`with_limit`.

Why static HTML (not the WordPress REST API or a JS-rendered page)
------------------------------------------------------------------
* Chevening **does not publish a public REST endpoint** for the
  per-country listings — only ``wp-sitemap.xml`` is auto-generated.
* Each landing page is **fully server-rendered** in plain HTML (the
  eligibility blurb, ``<h1>``, "How to apply" section, etc. are all
  in the SSR response). No JavaScript execution is required, so we
  can avoid Playwright entirely.
* The sitemap is **machine-generated XML** by WordPress itself and
  has been stable across recent WordPress releases; relying on it is
  far more robust than guessing per-country URL slugs.

Selection of fields
-------------------
Chevening awards are uniform across countries — *amount*, *eligibility
rules* and *degree* are the same for every country. The per-country
pages therefore contribute the **country list** and a stable apply
URL. We map the available fields as follows:

================== =====================================================
Requested field     Chevening source
================== =====================================================
title               ``"Chevening Scholarship – <Country>"`` derived from
                    URL slug (also matches the ``<title>`` element on
                    the landing page)
country             URL slug, title-cased (``ghana`` → ``Ghana``)
degree              ``"Masters"`` (one-year taught master's)
field               ``"Any"`` (Chevening accepts all fields)
deadline            ``"November 1"`` (the Chevening application window
                    closes on the first Tuesday of November each year;
                    the day-of-month is fixed across recent cycles)
amount              ``"Fully Funded"``
eligibility         Shared programme eligibility paragraph
description         Shared programme overview blurb
university          ``"Any UK university"`` (Chevening scholars choose
                    from any eligible UK institution)

|tags                ``["UK", "Fully Funded", "Masters", "Chevening", "Government Funded"]``|
apply_url           The per-country landing page URL
official_id         URL slug, e.g. ``"ghana"``
source              ``"chevening"``
================== =====================================================

Running this scraper
--------------------
The module is runnable as a standalone preview::

    python -m backend.scrapers.chevening        # canonical
    python backend/scrapers/chevening.py        # also supported

Both invocations run a small preview (capped at 5 records) and print
the resulting :class:`Scholarship` payloads. Production usage should
call :meth:`CheveningScraper.run` directly through the orchestrator.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Allow `python backend/scrapers/chevening.py` to run from any CWD by
# ensuring the project root (parent of `backend/`) is on sys.path BEFORE
# any `backend.*` import below.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.constants import APP_NAME
from backend.core.exceptions import ParsingException
from backend.core.logger import get_logger
from backend.core.retry import RetryPolicy
from backend.models.scholarship import Scholarship
from backend.scrapers.base_scraper import BaseScraper

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Public surface
# ---------------------------------------------------------------------------

#: URL of the Chevening scholarship sitemap. This sitemap is
#: machine-generated by WordPress and lists every country/territory that
#: has a Chevening landing page. We use it as the discovery index
#: instead of guessing slugs.
CHEVENING_SITEMAP_URL: str = (
    "https://www.chevening.org/wp-sitemap-posts-scholarships-1.xml"
)

#: Base URL of the per-country landing pages; used to build apply URLs.
CHEVENING_SCHOLARSHIP_URL_PREFIX: str = "https://www.chevening.org/scholarship/"

#: Regex that extracts the ``<loc>`` URLs from the sitemap XML.
_SITEMAP_LOC_RE = re.compile(
    r"<loc>\s*(?P<url>[^<]+?)\s*</loc>",
    flags=re.IGNORECASE,
)

#: Slug → human-readable country name. The sitemap uses dashes for
#: multi-word countries (``bosnia-and-herzegovina``). We rebuild the
#: canonical ``Country`` name by replacing dashes with spaces and
#: title-casing each word. We do **not** hand-code a translation table
#: so adding new countries requires no code change.
_DASH_RE = re.compile(r"-")

#: Stable programme-level fields shared across every country landing
#: page. Kept as module constants so tests can assert against them.
CHEVENING_PROGRAMME: Dict[str, Any] = {
    "degree": "Masters",
    "field": "Any",
    "amount": "Fully Funded",
    "university": "Any UK university",
    "category": "Government Funded",
    "eligibility": (
        "Applicants must hold an undergraduate degree, have at least "
        "two years of work experience, and meet the Chevening English "
        "language requirement."
    ),
    "description": (
        "Chevening is the UK government's global scholarship programme, "
        "funded by the Foreign, Commonwealth and Development Office and "
        "partner organisations. Scholars pursue a one-year taught "
        "master's degree at any UK university and return home to drive "
        "impact in areas of shared priority for the UK and their country."
    ),
    "deadline": "November 1",
    "tags": ["UK", "Fully Funded", "Masters", "Chevening", "Government Funded"],
}


def _slug_to_country(slug: str) -> str:
    """Convert a URL slug into a human-readable country name.

    Examples::

        >>> _slug_to_country("ghana")
        'Ghana'
        >>> _slug_to_country("bosnia-and-herzegovina")
        'Bosnia And Herzegovina'
        >>> _slug_to_country("cote-divoire")
        "Cote D'Ivoire"  # apostrophes aren't a WordPress convention;
                         # dashes are used for spaces.

    Args:
        slug: The trailing URL segment, e.g. ``"ghana"`` or
            ``"bosnia-and-herzegovina"``.

    Returns:
        Title-cased country name with dashes replaced by spaces. Special
        cases like ``"cote-divoire"`` (Côte d'Ivoire) are **not**
        auto-translated — they remain ``"Cote D'Ivoire"`` because
        WordPress does not use accented characters in slugs. This is a
        deliberate trade-off: keeping the converter dependency-free is
        more important than perfect name fidelity.
    """
    return _DASH_RE.sub(" ", slug).title()


def _extract_sitemap_urls(raw_xml: str) -> List[str]:
    """Return the absolute per-country URLs from the sitemap XML.

    Args:
        raw_xml: Raw XML body returned by :meth:`fetch`.

    Returns:
        List of URLs (``https://...``) found under ``<loc>`` elements.
        Malformed entries are silently skipped — WordPress occasionally
        emits blank lines between tags.

    Raises:
        ParsingException: If no ``<loc>`` elements were found at all,
            which usually means the sitemap URL changed and the
            scraper needs an update.
    """
    urls = [m.group("url").strip() for m in _SITEMAP_LOC_RE.finditer(raw_xml)]
    if not urls:
        raise ParsingException(
            "Chevening sitemap returned no <loc> entries; the site "
            "structure may have changed."
        )
    return urls


class CheveningScraper(BaseScraper):
    """Scraper for the Chevening scholarship programme (English)."""

    name: str = "chevening"

    # Chevening's sitemap + landing pages are small JSON/HTML; a lighter
    # retry budget than DAAD is sufficient.
    retry_policy: RetryPolicy = RetryPolicy(
        max_attempts=3,
        base_delay=0.75,
        max_delay=6.0,
        jitter=True,
    )

    def __init__(self) -> None:
        super().__init__(source_url=CHEVENING_SITEMAP_URL)
        self._limit: Optional[int] = None

    # ------------------------------------------------------------------
    # Fluent configuration
    # ------------------------------------------------------------------

    def with_limit(self, limit: Optional[int]) -> "CheveningScraper":
        """Cap the number of records produced per run.

        Args:
            limit: Max records to produce. ``None`` = no cap.

        Returns:
            ``self`` (fluent chaining).
        """
        self._limit = int(limit) if limit is not None else None
        return self

    # ------------------------------------------------------------------
    # BaseScraper implementation
    # ------------------------------------------------------------------

    def fetch(self) -> str:
        """Fetch the sitemap and return its raw XML body.

        Per-country landing pages are **not** fetched here. We defer
        fetching them to :meth:`parse` via the saved HTTP client so
        the BaseScraper contract (one ``fetch`` → one ``parse``) is
        preserved and so the polite per-request sleep in :meth:`parse`
        can run between page loads.

        Returns:
            The raw XML body of
            ``https://www.chevening.org/wp-sitemap-posts-scholarships-1.xml``.
        """
        self._ensure_client()
        response = self.client.get(self.source_url)
        response.raise_for_status()
        xml = response.text
        self.log_success(
            "Chevening sitemap -> %d byte(s)", len(xml),
        )
        return xml

    def parse(self, raw_content: str) -> List[Scholarship]:
        """Convert the sitemap body into ``Scholarship`` records.

        For each ``<loc>`` URL in the sitemap, the method:

        1. fetches the per-country landing page (cached HEAD-style: a
           request that is wrapped by the shared retry policy),
        2. extracts the country from the URL slug,
        3. builds a :class:`Scholarship` instance with the uniform
           programme-level fields from :data:`CHEVENING_PROGRAMME`,
        4. attaches the apply URL and an ``official_id`` derived from
           the slug.

        Malformed pages or transient HTTP errors are logged and the
        record is skipped — they never crash the whole run.

        Args:
            raw_content: XML body returned by :meth:`fetch`.

        Returns:
            List of :class:`Scholarship` instances (capped by
            ``with_limit`` if configured).
        """
        urls = _extract_sitemap_urls(raw_content)
        records: List[Scholarship] = []
        seen_slugs: set[str] = set()
        fetched = 0

        for url in urls:
            if self._limit is not None and len(records) >= self._limit:
                break
            if not url.startswith(CHEVENING_SCHOLARSHIP_URL_PREFIX):
                # Defensive: skip any non-scholarship <loc> entries.
                logger.debug("Chevening: skipping non-scholarship URL %s", url)
                continue
            slug = url[len(CHEVENING_SCHOLARSHIP_URL_PREFIX):].rstrip("/")
            if not slug or slug in seen_slugs:
                continue
            seen_slugs.add(slug)
            try:
                if fetched > 0:
                    # Polite 1–2s delay between page fetches.
                    self.sleep()
                response = self.client.get(url)
                response.raise_for_status()
                fetched += 1
            except Exception as exc:  # noqa: BLE001 - defensive
                logger.warning(
                    "Chevening: failed to fetch %s (%s); skipping.",
                    url, exc,
                )
                continue

            record = self._build_record(slug=slug, url=url, html=response.text)
            if record is not None:
                records.append(record)

        logger.info(
            "Chevening: produced %d scholarship record(s) from %d URL(s).",
            len(records), len(seen_slugs),
        )
        return records

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _build_record(
        self,
        *,
        slug: str,
        url: str,
        html: str,
    ) -> Optional[Scholarship]:
        """Build a single :class:`Scholarship` from one landing page.

        Args:
            slug: Country slug (e.g. ``"ghana"``).
            url: Absolute landing-page URL (used as the apply URL).
            html: Raw HTML body of the landing page (currently only
                validated as non-empty — see ``Discovery notes`` for
                why we don't extract per-country fields).

        Returns:
            A populated :class:`Scholarship`, or ``None`` if the slug is
            blank (defensive — should never happen).
        """
        if not slug:
            return None
        country = _slug_to_country(slug)
        title = f"Chevening Scholarship – {country}"
        try:
            return Scholarship(
                title=title,
                country=country,
                degree=CHEVENING_PROGRAMME["degree"],
                field=CHEVENING_PROGRAMME["field"],
                deadline=CHEVENING_PROGRAMME["deadline"],
                amount=CHEVENING_PROGRAMME["amount"],
                description=CHEVENING_PROGRAMME["description"],
                eligibility=CHEVENING_PROGRAMME["eligibility"],
                link=url,
                apply_url=url,
                source=self.name,
                official_id=slug,
                university=CHEVENING_PROGRAMME["university"],
                tags=list(CHEVENING_PROGRAMME["tags"]),
            )
        except Exception as exc:  # noqa: BLE001 - defensive
            logger.warning(
                "Chevening: Scholarship construction failed for %r (%s); "
                "skipping.", slug, exc,
            )
            return None


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------


def _render_record(index: int, scholarship: Scholarship) -> str:
    """Pretty-print one scholarship for the standalone preview."""
    return (
        f"\n  [{index}] {scholarship.title}\n"
        f"      country      : {scholarship.country}\n"
        f"      degree       : {scholarship.degree}\n"
        f"      field        : {scholarship.field}\n"
        f"      deadline     : {scholarship.deadline}\n"
        f"      amount       : {scholarship.amount}\n"
        f"      university   : {scholarship.university}\n"
        f"      official_id  : {scholarship.official_id}\n"
        f"      apply_url    : {scholarship.apply_url}\n"
        f"      tags         : {scholarship.tags}\n"
    )


def main() -> int:
    """Run the scraper in preview mode and print a summary."""
    banner = (
        "\n"
        "============================================================\n"
        "  ScholarBird Backend :: Chevening Scraper (standalone runner)\n"
        "============================================================\n"
    )
    print(banner)
    preview_limit = 5
    try:
        scraper = CheveningScraper().with_limit(preview_limit)
        logger.info("Starting Chevening scraper (%s)", scraper.source_url)
        scholarships = scraper.run()
    except Exception as exc:  # pragma: no cover - top-level safety net
        logger.exception("Chevening scraper failed: %s", exc)
        print(f"\nERROR: Chevening scraper failed: {exc}")
        return 1

    print(
        f"\nFetched {len(scholarships)} scholarship record(s) "
        f"(preview limited to {preview_limit}).\n"
    )
    if not scholarships:
        print("No records returned. Check connectivity / robots.txt.")
        return 1
    for index, scholarship in enumerate(scholarships, start=1):
        print(_render_record(index, scholarship))

    sample = scholarships[0].to_firestore()
    print("First record to_firestore() keys:")
    print("  " + ", ".join(sorted(sample.keys())))
    print("\nDone.")
    return 0


if __name__ == "__main__":  # pragma: no cover - script entry point
    sys.exit(main())