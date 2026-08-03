"""Smoke test runner for the Generic Scraper Engine.

This file is the manual harness the team uses to verify that:

* the discovery layer finds every concrete scraper,
* the BaseScraper request / retry / throttle pipeline works,
* the Scholarship model serialises and validates as expected.

It is **not** part of the pytest suite (no ``test_*`` filename and no
assertion framework). It prints a human-friendly report and exits with
a non-zero status when something is wrong.

Run with either::

    python backend/tests/test_runner.py
    python -m backend.tests.test_runner
"""
from __future__ import annotations

import sys
import time
from pathlib import Path
from typing import Iterable, List

# Ensure the project root is on ``sys.path`` so ``import backend.*``
# works regardless of the working directory.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.settings import get_settings  # noqa: E402
from backend.core.exceptions import (  # noqa: E402
    ScraperException,
    ValidationError,
)
from backend.core.logger import configure_logging, get_logger  # noqa: E402
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.run_scraper import (  # noqa: E402
    ScraperResult,
    discover_scrapers,
    run_many,
)

logger = get_logger(__name__)

PREVIEW_LIMIT: int = 5


# ---------------------------------------------------------------------------
# Reporting helpers
# ---------------------------------------------------------------------------


def _truncate(text: str | None, limit: int = 80) -> str:
    """Shorten ``text`` to ``limit`` characters with an ellipsis."""
    if not text:
        return "-"
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _render_record(index: int, s: Scholarship) -> str:
    """Format a single scholarship for stdout."""
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


def _render_summary(results: List[ScraperResult]) -> str:
    """Render a final summary table."""
    lines: list[str] = ["", "Summary:", "-" * 60]
    total_records = 0
    total_elapsed = 0.0
    for result in results:
        if result.ok:
            status = f"OK    {len(result.records):>4} records"
        else:
            status = f"FAIL  {result.error}"
        lines.append(
            f"  {result.name:<20} {result.elapsed_seconds:>7.2f}s   {status}"
        )
        total_records += len(result.records)
        total_elapsed += result.elapsed_seconds
    lines.append("-" * 60)
    lines.append(
        f"  {'TOTAL':<20} {total_elapsed:>7.2f}s   {total_records:>4} records"
    )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def _check_discovery() -> None:
    """Print the list of registered scrapers and assert at least one exists."""
    registry = discover_scrapers()
    print("\nDiscovered scrapers:")
    if not registry:
        raise RuntimeError(
            "No concrete scrapers found in backend.scrapers. "
            "Did you forget to set the class attribute `name`?"
        )
    for name, cls in registry.items():
        print(f"  - {name:<20} {cls.__module__}.{cls.__name__}")


def _validate_sample(records: Iterable[Scholarship]) -> int:
    """Run :meth:`Scholarship.validate` on a sample; count failures."""
    failures = 0
    for record in records:
        try:
            record.validate(raise_on_error=True)
        except ValidationError as exc:
            failures += 1
            logger.warning(
                "Validation failed for %s: %s",
                record.official_id or record.title,
                exc,
            )
    return failures


def _check_serialisation(records: List[Scholarship]) -> None:
    """Round-trip ``to_dict`` -> ``from_dict`` on the first record."""
    if not records:
        return
    sample = records[0]
    snapshot = sample.to_dict()
    rebuilt = Scholarship.from_dict(snapshot)
    if rebuilt.to_dict() != snapshot:
        raise RuntimeError(
            "Scholarship.from_dict did not round-trip to_dict() faithfully."
        )
    print("\nFirst record to_dict() keys:")
    print("  " + ", ".join(sorted(snapshot.keys())))


def main(names: List[str] | None = None, *, limit: int | None = PREVIEW_LIMIT) -> int:
    """Run the smoke test harness.

    Args:
        names: Optional explicit list of scraper names to run. When
            ``None``, every discovered scraper is executed.
        limit: Per-scraper record cap forwarded to each scraper.

    Returns:
        ``0`` on success, ``1`` on any failure.
    """
    settings = get_settings()
    configure_logging(level=settings.log_level)

    banner = (
        "\n"
        "============================================================\n"
        "  ScholarBird Backend :: Generic Scraper Engine (test runner)\n"
        "============================================================\n"
    )
    print(banner)

    started = time.perf_counter()
    try:
        _check_discovery()

        registry = discover_scrapers()
        target_names = list(names) if names else list(registry.keys())
        if not target_names:
            raise RuntimeError("No scrapers selected (registry is empty).")

        results = run_many(target_names, limit=limit)
    except ScraperException as exc:
        logger.error("Discovery failed: %s", exc)
        print(f"\nERROR: discovery failed: {exc}")
        return 1
    except Exception as exc:  # noqa: BLE001 - top-level safety net
        logger.exception("Test runner crashed: %s", exc)
        print(f"\nERROR: test runner crashed: {exc}")
        return 1

    total_records = 0
    for result in results:
        total_records += len(result.records)
        if not result.ok:
            continue
        print(
            f"\nScraper {result.name!r} produced {len(result.records)} record(s) "
            f"in {result.elapsed_seconds:.2f}s."
        )
        # Print at most PREVIEW_LIMIT records per scraper.
        for index, scholarship in enumerate(
            result.records[:PREVIEW_LIMIT], start=1
        ):
            print(_render_record(index, scholarship))

        # Validate a sample of records.
        failures = _validate_sample(result.records[:PREVIEW_LIMIT])
        if failures:
            print(f"  ⚠️  {failures} record(s) failed validation.")
        else:
            print("  ✓ All previewed records passed validation.")

        # Round-trip check.
        _check_serialisation(result.records)

    elapsed = time.perf_counter() - started
    print(_render_summary(results))
    print(f"\nRunner wall time: {elapsed:.2f}s")
    print("Done.")
    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
