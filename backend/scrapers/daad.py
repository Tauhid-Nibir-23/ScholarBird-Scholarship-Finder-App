"""DAAD scholarship-database scraper.

Discovery notes
---------------
The DAAD scholarship database at
``https://www2.daad.de/deutschland/stipendium/datenbank/en/21148-scholarship-database/``
ships its dataset to the browser via plain ``var x = TAFFY([...])`` data
files. They live at::

    https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/
        origin.js
        scholarships.js   <-- 161 scholarship records
        status.js
        subjectgroups.js
        intentions.js
        deadlines.js

There is **no JSON or HTML fallback** — the listing page is a JS-only
shell, but the data files themselves are vanilla JSON wrapped in a
``TAFFY([...])`` call that we strip before parsing.

Robots / ethics
---------------
DAAD's ``robots.txt`` explicitly disallows the *legacy*
``/deutschland/stipendium/datenbank/00462...en/`` URL but the modern
``.../21148-scholarship-database/`` listing and its data bundles are
**not disallowed**. We still:

* identify ourselves with a descriptive ``User-Agent``
  (``ScholarBirdBot/1.0 (+https://scholarbird.app)`` — configured via
  ``SCRAPER_USER_AGENT``),
* serialise requests on a single HTTP/1.1 connection,
* honour the configurable per-request timeout from ``settings``,
* throttle 1–2 s between successive fetches
  (configurable via :attr:`BaseScraper.min_request_delay` and
  :attr:`max_request_delay`).

Selection of fields
-------------------
DAAD does **not** expose a dedicated *funding amount*, *apply URL*, or
*university* column. We map the available fields as follows:

================== =====================================================
Requested field     DAAD source
================== =====================================================
title               ``nameEn``
country             ``origin[0]`` resolved against ``origin.js``
degree              ``status[*]`` resolved against ``status.js``
field               ``subjectGrps[*]`` resolved against ``subjectgroups.js``
deadline            ``deadlines.id == sapProgid -> general.en``
funding / amount    ``""`` (DAAD has no amount column; left blank)
eligibility         ``introduction.en`` (best-effort program overview)
description         ``introduction.en``
university          ``programmnameEn`` (DAAD's umbrella program name)
category            comma-joined ``subjectGrps.nameEn``
apply_url           listing-page URL with the scholarship ``id``
official_id         ``str(id)``
source              ``"daad"``
================== =====================================================

Running this scraper
--------------------
The module is runnable both ways::

    python -m backend.scrapers.daad              # canonical
    python backend/scrapers/daad.py              # also supported

Both invocations run a 5-record preview identical to the legacy
``backend/test_daad.py`` smoke test. Production usage should call
:meth:`DaadScraper.run` directly.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Allow `python backend/scrapers/daad.py` to run from any CWD by ensuring
# the project root (parent of `backend/`) is on sys.path BEFORE any
# `backend.*` import below.
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

#: URL of the human-facing listing page (used in logs, metadata, fallback).
DAAD_LISTING_URL: str = (
    "https://www2.daad.de/deutschland/stipendium/datenbank/en/"
    "21148-scholarship-database/"
)

#: Base URL of the data bundles discovered in the listing page source.
DAAD_DATA_BASE_URL: str = (
    "https://www2.daad.de/bundles/daadstipendiendatenbanklsh/data/a/js/"
)

#: Bundle files we need to fetch (relative to :data:`DAAD_DATA_BASE_URL`).
_DATA_FILES: tuple[str, ...] = (
    "scholarships.js",      # 161 scholarship records
    "origin.js",            # countries -> id
    "status.js",            # degree level -> id
    "subjectgroups.js",     # fields of study -> id
    "intentions.js",        # purpose of study -> id
    "deadlines.js",         # deadline text keyed by sapProgid
)

#: Regex that strips the ``var x = TAFFY(...)`` wrapping from each file.
_TAFFY_WRAPPER_RE = re.compile(
    r"^\s*var\s+\w+\s*=\s*TAFFY\(\s*(?P<body>.*)\s*\)\s*;\s*$",
    re.DOTALL,
)


class DaadScraper(BaseScraper):
    """Scraper for the DAAD scholarship database (English)."""

    name: str = "daad"

    # DAAD's JS bundles are large; bumps the default retry budget.
    retry_policy: RetryPolicy = RetryPolicy(
        max_attempts=3,
        base_delay=1.0,
        max_delay=8.0,
        jitter=True,
    )

    def __init__(self) -> None:
        super().__init__(source_url=DAAD_LISTING_URL)
        # Cap on the number of records produced (used by tests / callers
        # that want a tiny batch). Production callers leave it at ``None``.
        self._limit: Optional[int] = None

    # ------------------------------------------------------------------
    # Fluent configuration
    # ------------------------------------------------------------------

    def with_limit(self, limit: Optional[int]) -> "DaadScraper":
        """Return ``self`` with an optional cap on the number of records.

        Useful for the standalone test runner — production callers leave
        the limit at ``None`` to ingest the full database.

        Args:
            limit: Max number of records to produce. ``None`` = no cap.

        Returns:
            The same instance (for fluent chaining).
        """
        self._limit = int(limit) if limit is not None else None
        return self

    # ------------------------------------------------------------------
    # BaseScraper implementation
    # ------------------------------------------------------------------

    def fetch(self) -> str:
        """Fetch every DAAD data bundle and serialise the snapshot.

        The fetched payload is JSON-encoded so :meth:`parse` can ingest
        it without depending on httpx or the caller's runtime.

        Returns:
            A JSON document with the keys ``scholarships``, ``origin``,
            ``status``, ``subjectgroups``, ``intentions``, ``deadlines``.
        """
        self._ensure_client()
        snapshot: Dict[str, Any] = {}
        for index, filename in enumerate(_DATA_FILES):
            if index > 0:
                # Polite 1–2s delay between successive fetches.
                self.sleep()
            body = self._fetch_one(filename)
            parsed = _extract_taffy_payload(body, filename)
            snapshot[filename.removesuffix(".js")] = parsed
            self.log_success(
                "DAAD %-14s -> %d record(s)",
                filename,
                len(parsed),
            )
        return json.dumps(snapshot, ensure_ascii=False)

    def parse(self, raw_content: str) -> List[Scholarship]:
        """Convert a :meth:`fetch` snapshot into ``Scholarship`` records.

        Args:
            raw_content: JSON string produced by :meth:`fetch`.

        Returns:
            A list of fully-populated :class:`Scholarship` instances.

        Raises:
            ParsingException: When the snapshot cannot be decoded.
        """
        try:
            snapshot: Dict[str, Any] = json.loads(raw_content)
        except json.JSONDecodeError as exc:
            raise ParsingException(
                f"DAAD scraper could not decode snapshot: {exc}",
                source=self.name,
            ) from exc

        scholarships_raw: List[Dict[str, Any]] = snapshot.get("scholarships", [])
        origins: Dict[int, str] = {
            int(o["id"]): o.get("nameEn") or o.get("nameDe") or ""
            for o in snapshot.get("origin", [])
            if "id" in o
        }
        statuses: Dict[int, str] = {
            int(s["id"]): s.get("nameEn") or s.get("nameDe") or ""
            for s in snapshot.get("status", [])
            if "id" in s
        }
        subject_groups: Dict[str, str] = {
            str(sg["code"]): sg.get("nameEn") or sg.get("nameDe") or ""
            for sg in snapshot.get("subjectgroups", [])
            if "code" in sg
        }
        intentions: Dict[int, str] = {
            int(i["id"]): i.get("nameEn") or i.get("nameDe") or ""
            for i in snapshot.get("intentions", [])
            if "id" in i
        }
        deadlines_by_id: Dict[int, Dict[str, str]] = {
            int(d["id"]): d.get("general", {}) or {}
            for d in snapshot.get("deadlines", [])
            if "id" in d
        }

        records: List[Scholarship] = []
        cap = self._limit if self._limit is not None else len(scholarships_raw)
        for raw in scholarships_raw[:cap]:
            try:
                records.append(
                    self._build_scholarship(
                        raw,
                        origins=origins,
                        statuses=statuses,
                        subject_groups=subject_groups,
                        intentions=intentions,
                        deadlines_by_id=deadlines_by_id,
                    )
                )
            except (KeyError, TypeError, ValueError) as exc:
                logger.warning(
                    "Skipping DAAD record id=%s due to %s",
                    raw.get("id"),
                    exc,
                )

        logger.info(
            "%s parsed %d/%d DAAD scholarship record(s)",
            APP_NAME,
            len(records),
            min(cap, len(scholarships_raw)),
        )
        return records

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _fetch_one(self, filename: str) -> str:
        """Fetch a single DAAD data bundle via the base :meth:`request`.

        Args:
            filename: Name of the JS bundle under
                :data:`DAAD_DATA_BASE_URL`.

        Returns:
            The raw response body as text.

        Raises:
            backend.core.exceptions.NetworkException: When the HTTP
                response is not 2xx or the body is empty.
        """
        url = DAAD_DATA_BASE_URL + filename
        response = self.request(url)
        body = response.text
        if not body.strip():
            from backend.core.exceptions import NetworkException

            raise NetworkException(
                f"DAAD data fetch returned an empty body for {filename}",
                url=url,
                status_code=response.status_code,
            )
        return body

    def _build_scholarship(
        self,
        raw: Dict[str, Any],
        *,
        origins: Dict[int, str],
        statuses: Dict[int, str],
        subject_groups: Dict[str, str],
        intentions: Dict[int, str],
        deadlines_by_id: Dict[int, Dict[str, str]],
    ) -> Scholarship:
        """Map a raw DAAD record to a typed :class:`Scholarship`.

        Args:
            raw: One DAAD record from ``scholarships.js``.
            origins / statuses / subject_groups / intentions: Lookup maps
                resolved by :meth:`parse`.
            deadlines_by_id: Pre-extracted deadline text keyed by
                ``sapProgid``.

        Returns:
            A populated :class:`Scholarship` instance.
        """
        sap_prog_id: Optional[int] = raw.get("sapProgid")
        deadline_text: str = ""
        if sap_prog_id is not None:
            deadline_text = (
                deadlines_by_id.get(sap_prog_id, {}).get("en", "") or ""
            )
        deadline_text = _strip_html(deadline_text)

        status_labels: List[str] = _resolve_many(statuses, raw.get("status", []))
        subject_labels: List[str] = _resolve_subject_groups(
            raw.get("subjectGrps", []), subject_groups
        )
        intention_labels: List[str] = _resolve_many(
            intentions, raw.get("intentions", [])
        )

        title: str = (raw.get("nameEn") or raw.get("nameDe") or "").strip()
        description_text: str = (
            (raw.get("introduction") or {}).get("en", "")
            or (raw.get("introduction") or {}).get("de", "")
            or ""
        ).strip()
        university: str = (
            raw.get("programmnameEn") or raw.get("programmnameDe") or ""
        ).strip()

        # Tags: free-form classification assembled from IDs we have labels for.
        tags: List[str] = []
        if subject_labels:
            tags.extend(subject_labels)
        if status_labels:
            tags.extend(status_labels)
        if intention_labels:
            tags.extend(intention_labels)

        record_id = raw.get("id")
        program_id = raw.get("sapProgid")
        official_id = (
            f"daad-{record_id}" if record_id is not None else None
        )

        scholarship = Scholarship(
            title=title or "(untitled)",
            # DAAD programs are listed once but may cover 100+ origin
            # countries. We do NOT pick the first origin (that would
            # misrepresent a global programme as one-country). Instead we
            # default to "Germany" (the host country of every programme)
            # and surface the full origin list via the eligibility field.
            country="Germany",
            degree=", ".join(status_labels),
            field=", ".join(subject_labels),
            deadline=(
                deadline_text
                or "See official page"
            ),
            amount="",  # DAAD exposes no amount column
            description=description_text,
            link=DAAD_LISTING_URL,
            source=self.name,
            tags=tags,
            university=university or None,
            official_id=official_id,
            eligibility=_build_eligibility_text(
                description_text,
                origins=origins,
                origin_ids=raw.get("origin", []),
            ),
            apply_url=(
                f"{DAAD_LISTING_URL}?detail={program_id}"
                if program_id is not None
                else None
            ),
        )
        logger.debug(
            "Mapped DAAD id=%s -> %s (%s)",
            record_id,
            scholarship.title,
            scholarship.country,
        )
        return scholarship


# ---------------------------------------------------------------------------
# Module-level helpers
# ---------------------------------------------------------------------------

def _extract_taffy_payload(body: str, filename: str) -> List[Dict[str, Any]]:
    """Strip the ``var x = TAFFY([...])`` wrapper and parse the body as JSON.

    Args:
        body: Raw response text.
        filename: Used only for log/error context.

    Returns:
        The decoded payload as a list of dicts.

    Raises:
        ParsingException: When the wrapper is malformed or the body is
            not valid JSON.
    """
    match = _TAFFY_WRAPPER_RE.match(body)
    if not match:
        raise ParsingException(
            f"DAAD data file {filename!r} does not match TAFFY wrapper",
            source=filename,
        )
    raw_json = match.group("body")
    try:
        return json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ParsingException(
            f"DAAD data file {filename!r} is not valid JSON: {exc}",
            source=filename,
        ) from exc


def _resolve_many(lookup: Dict[int, str], ids: Any) -> List[str]:
    """Map a list of IDs to their labels, dropping unknowns.

    Args:
        lookup: ``id -> label`` mapping.
        ids: Iterable of IDs.

    Returns:
        Resolved labels in input order, duplicates removed.
    """
    seen: set[str] = set()
    resolved: List[str] = []
    for raw_id in ids or []:
        try:
            int_id = int(raw_id)
        except (TypeError, ValueError):
            continue
        label = lookup.get(int_id)
        if label and label not in seen:
            resolved.append(label)
            seen.add(label)
    return resolved


def _resolve_subject_groups(
    codes: Any, lookup: Dict[str, str]
) -> List[str]:
    """Map a list of subject-group codes to their labels.

    Args:
        codes: Iterable of single-letter codes (``"A"``–``"G"``).
        lookup: ``code -> label`` mapping (codes are strings in DAAD).

    Returns:
        Resolved labels in input order.
    """
    resolved: List[str] = []
    for code in codes or []:
        label = lookup.get(str(code))
        if label:
            resolved.append(label)
    return resolved


_HTML_TAG_RE = re.compile(r"<[^>]+>")


def _strip_html(text: str) -> str:
    """Remove HTML tags and collapse whitespace from ``text``.

    Args:
        text: Possibly HTML-bearing string (DAAD encodes ``<br />`` etc.).

    Returns:
        A plain-text version suitable for storage in ``Scholarship.deadline``.
    """
    if not text:
        return ""
    cleaned = _HTML_TAG_RE.sub(" ", text)
    return " ".join(cleaned.split()).strip()


# Cap on how many origin countries we paste into ``eligibility`` so the
# text stays readable and does not blow up Firestore document size.
_MAX_ORIGIN_COUNTRIES_IN_ELIGIBILITY: int = 12


def _build_eligibility_text(
    description: str,
    *,
    origins: Dict[int, str],
    origin_ids: Any,
) -> Optional[str]:
    """Compose a short eligibility sentence from description + origins.

    Args:
        description: Free-form programme description (English).
        origins: ``id -> country name`` lookup table.
        origin_ids: Iterable of origin IDs from the DAAD record.

    Returns:
        A combined string, or ``None`` when both inputs are empty.
    """
    resolved: List[str] = []
    seen: set[str] = set()
    for raw_id in origin_ids or []:
        try:
            int_id = int(raw_id)
        except (TypeError, ValueError):
            continue
        name = origins.get(int_id)
        if name and name not in seen:
            resolved.append(name)
            seen.add(name)
        if len(resolved) >= _MAX_ORIGIN_COUNTRIES_IN_ELIGIBILITY:
            break

    parts: List[str] = []
    if resolved:
        if len(resolved) < _MAX_ORIGIN_COUNTRIES_IN_ELIGIBILITY:
            parts.append("Eligible nationalities: " + ", ".join(resolved) + ".")
        else:
            parts.append(
                "Eligible nationalities include: "
                + ", ".join(resolved)
                + ", and others (see official page)."
            )
    if description:
        parts.append(description)
    text = " ".join(parts).strip()
    return text or None


__all__ = ["DaadScraper"]


# ---------------------------------------------------------------------------
# ``__main__`` block — works for BOTH invocations:
#   * python -m backend.scrapers.daad
#   * python backend/scrapers/daad.py
# ---------------------------------------------------------------------------

_PREVIEW_LIMIT: int = 5


def _bootstrap_sys_path() -> None:
    """Ensure the project root is on ``sys.path`` for direct script runs.

    ``python backend/scrapers/daad.py`` does not automatically put the
    directory containing ``backend/`` on ``sys.path`` the way
    ``python -m backend.scrapers.daad`` does, so absolute imports of
    ``backend.*`` would fail. This is a one-line shim that mirrors the
    behaviour used by :mod:`backend.main`.
    """
    project_root = Path(__file__).resolve().parent.parent.parent
    if str(project_root) not in sys.path:
        sys.path.insert(0, str(project_root))


def _print_preview(scholarships: List[Scholarship]) -> None:
    """Render a 5-row preview of the parsed scholarships to stdout."""
    for index, scholarship in enumerate(scholarships[:_PREVIEW_LIMIT], start=1):
        print(
            f"\n--- #{index} -----------------------------------------------\n"
            f"  Title       : {scholarship.title}\n"
            f"  Country     : {scholarship.country}\n"
            f"  Degree      : {scholarship.degree or '-'}\n"
            f"  Field       : {scholarship.field or '-'}\n"
            f"  Deadline    : {scholarship.deadline[:80]}\n"
            f"  University  : {scholarship.university or '-'}\n"
            f"  Official ID : {scholarship.official_id or '-'}\n"
            f"  Apply URL   : {scholarship.apply_url or '-'}\n"
            f"  Source      : {scholarship.source}\n"
            f"  Tags        : {', '.join(scholarship.tags)[:120]}\n"
            f"  Eligibility : {(scholarship.eligibility or '')[:200]}\n"
            f"  Description : {(scholarship.description or '')[:200]}\n"
        )


def _main() -> int:
    """Run the DAAD scraper and print a 5-row preview.

    Returns:
        ``0`` on success, ``1`` on any failure.
    """
    _bootstrap_sys_path()

    print(
        "\n"
        "============================================================\n"
        "  ScholarBird Backend :: DAAD Scraper (direct runner)\n"
        "============================================================\n"
    )

    try:
        with DaadScraper().with_limit(_PREVIEW_LIMIT) as scraper:
            logger.info("Starting DAAD scraper (%s)", scraper.source_url)
            scholarships = scraper.run()
    except Exception as exc:  # pragma: no cover - top-level safety net
        logger.exception("DAAD scraper failed: %s", exc)
        print(f"\nERROR: DAAD scraper failed: {exc}")
        return 1

    print(
        f"\nFetched {len(scholarships)} scholarship record(s) "
        f"(preview limited to {_PREVIEW_LIMIT}).\n"
    )

    if not scholarships:
        print("No records returned. Check connectivity / robots.txt.")
        return 1

    _print_preview(scholarships)
    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
