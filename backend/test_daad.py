"""Standalone runner for the DAAD scraper.

Executes :class:`backend.scrapers.daad.DaadScraper` and prints the
first five parsed :class:`backend.models.Scholarship` records in a
human-readable table.

Run from the project root::

    python backend/test_daad.py

The script exits with a non-zero status code on failure so it can be
plugged into CI.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

# Ensure ``import backend.*`` works when run as ``python backend/test_daad.py``.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.core.logger import get_logger  # noqa: E402
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.scrapers.daad import DaadScraper  # noqa: E402

logger = get_logger(__name__)

PREVIEW_LIMIT: int = 5


def _truncate(text: Optional[str], limit: int = 80) -> str:
    """Shorten a string to ``limit`` characters with an ellipsis.

    Args:
        text: Text to limit. ``None`` or empty renders as ``"-"``.
        limit: Maximum allowed length.

    Returns:
        The (possibly truncated) string.
    """
    if not text:
        return "-"
    return text if len(text) <= limit else text[: limit - 3] + "..."


def render_scholarship(index: int, s: Scholarship) -> str:
    """Format a single scholarship as a boxed block.

    Args:
        index: 1-based row number for the header.
        s: The scholarship to render.

    Returns:
        A multi-line string suitable for stdout.
    """
    return (
        f"\n--- #{index} -----------------------------------------------\n"
        f"  Title       : {s.title}\n"
        f"  Country     : {s.country}\n"
        f"  Degree      : {s.degree or '-'}\n"
        f"  Field       : {s.field or '-'}\n"
        f"  Deadline    : {_truncate(s.deadline)}\n"
        f"  University  : {s.university or '-'}\n"
        f"  Official ID : {s.official_id or '-'}\n"
        f"  Apply URL   : {s.apply_url or '-'}\n"
        f"  Source      : {s.source}\n"
        f"  Tags        : {_truncate(', '.join(s.tags), 120)}\n"
        f"  Eligibility : {_truncate(s.eligibility, 200)}\n"
        f"  Description : {_truncate(s.description, 200)}\n"
    )


def main() -> int:
    """Execute the scraper and print a preview.

    Returns:
        ``0`` on success, ``1`` on any failure.
    """
    banner = (
        "\n"
        "============================================================\n"
        "  ScholarBird Backend :: DAAD Scraper (standalone runner)\n"
        "============================================================\n"
    )
    print(banner)

    try:
        scraper = DaadScraper().with_limit(PREVIEW_LIMIT)
        logger.info("Starting DAAD scraper (%s)", scraper.source_url)
        scholarships = scraper.run()
    except Exception as exc:  # pragma: no cover - top-level safety net
        logger.exception("DAAD scraper failed: %s", exc)
        print(f"\nERROR: DAAD scraper failed: {exc}")
        return 1

    print(f"\nFetched {len(scholarships)} scholarship record(s) "
          f"(preview limited to {PREVIEW_LIMIT}).\n")

    if not scholarships:
        print("No records returned. Check connectivity / robots.txt.")
        return 1

    for index, scholarship in enumerate(scholarships, start=1):
        print(render_scholarship(index, scholarship))

    # Also verify to_firestore() is callable on each record.
    sample = scholarships[0].to_firestore()
    print("\nFirst record to_firestore() keys:")
    print("  " + ", ".join(sorted(sample.keys())))

    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
