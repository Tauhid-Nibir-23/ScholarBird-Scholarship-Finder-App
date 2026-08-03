"""Generic Scraper Engine runner.

This CLI is the single entry point for executing any scraper currently
installed in :mod:`backend.scrapers`. It:

* discovers every :class:`BaseScraper` subclass in the package,
* lets the operator list, run one, or run them all,
* honours an optional ``--limit`` per scraper for smoke tests,
* prints a per-scraper summary (count, runtime, errors) and a grand
  total at the end,
* writes everything to the rotated ``backend.log`` /
  ``scraper.log`` / ``errors.log`` files via the configured logger.

Usage::

    python backend/run_scraper.py --list
    python backend/run_scraper.py --scraper daad --limit 5
    python backend/run_scraper.py --all
    python backend/run_scraper.py --all --limit 3

Both invocations are supported::

    python backend/run_scraper.py --list
    python -m backend.run_scraper --list
"""
from __future__ import annotations

import argparse
import importlib
import inspect
import pkgutil
import sys
import time
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Type

# ---------------------------------------------------------------------------
# sys.path bootstrap — supports ``python backend/run_scraper.py``
# ---------------------------------------------------------------------------
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from backend.config.settings import get_settings  # noqa: E402
from backend.core.logger import configure_logging, get_logger  # noqa: E402
from backend.models.scholarship import Scholarship  # noqa: E402
from backend.scrapers.base_scraper import BaseScraper  # noqa: E402

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ScraperEntry:
    """Lightweight description of a registered scraper."""

    name: str
    cls: Type[BaseScraper]
    signature: str

    def __str__(self) -> str:  # pragma: no cover - formatting helper
        return f"{self.name:<20} {self.cls.__module__}.{self.cls.__name__}"


def _is_scraper_concrete(cls: type) -> bool:
    """Return ``True`` when ``cls`` is a concrete :class:`BaseScraper` subclass.

    A class is considered concrete when:

    * it inherits from :class:`BaseScraper`,
    * it is not :class:`BaseScraper` itself,
    * it is not :data:`abc.ABCMeta`-abstract (i.e. all abstract methods
      are implemented).
    """
    if not isinstance(cls, type) or cls is BaseScraper:
        return False
    if not issubclass(cls, BaseScraper):
        return False
    return not inspect.isabstract(cls)


def discover_scrapers() -> Dict[str, Type[BaseScraper]]:
    """Import every module in :mod:`backend.scrapers` and collect subclasses.

    Returns:
        Ordered mapping ``name -> scraper class``. The mapping preserves
        the discovery order so ``--list`` output is stable across runs.
    """
    import backend.scrapers as scrapers_pkg

    found: Dict[str, Type[BaseScraper]] = {}
    for module_info in pkgutil.iter_modules(scrapers_pkg.__path__):
        if module_info.name.startswith("_"):
            continue
        module = importlib.import_module(f"{scrapers_pkg.__name__}.{module_info.name}")
        for _, obj in inspect.getmembers(module, inspect.isclass):
            if not _is_scraper_concrete(obj):
                continue
            if obj.__module__ != module.__name__:
                # Skip re-exports — we only want classes defined in *this* module.
                continue
            name = getattr(obj, "name", obj.__name__.lower())
            if name in found:
                # Avoid duplicates from cross-imports.
                continue
            found[name] = obj
    return found


def list_scrapers() -> List[ScraperEntry]:
    """Return a sorted list of :class:`ScraperEntry` for the CLI."""
    entries = [
        ScraperEntry(
            name=name,
            cls=cls,
            signature=f"{cls.__module__}.{cls.__name__}",
        )
        for name, cls in discover_scrapers().items()
    ]
    entries.sort(key=lambda entry: entry.name)
    return entries


# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------


@dataclass
class ScraperResult:
    """Outcome of a single scraper run."""

    name: str
    elapsed_seconds: float
    records: List[Scholarship]
    error: Optional[str] = None

    @property
    def ok(self) -> bool:
        """``True`` when the scraper ran without raising."""
        return self.error is None


def _instantiate_scraper(cls: Type[BaseScraper]) -> BaseScraper:
    """Build a scraper instance.

    DAAD and most simple scrapers take zero constructor arguments. If a
    future scraper needs settings overrides, it should accept them via
    keyword arguments on its ``__init__``.
    """
    try:
        return cls()
    except TypeError:
        # Fallback: try the older signature ``cls(source_url)``.
        source_url = getattr(cls, "default_source_url", "about:blank")
        return cls(source_url)


def _apply_limit(
    scraper: BaseScraper, limit: Optional[int]
) -> Optional[int]:
    """Apply ``limit`` to a scraper if it supports ``with_limit()``.

    Args:
        scraper: Concrete scraper instance.
        limit: Optional cap on the number of records.

    Returns:
        The ``limit`` when it was applied, otherwise ``None``.
    """
    if limit is None:
        return None
    setter = getattr(scraper, "with_limit", None)
    if callable(setter):
        setter(limit)
        return limit
    logger.warning(
        "Scraper %s does not support with_limit(); limit=%s ignored",
        scraper.name,
        limit,
    )
    return None


def run_scraper(
    name: str,
    cls: Type[BaseScraper],
    *,
    limit: Optional[int] = None,
) -> ScraperResult:
    """Execute a single scraper and capture its result.

    Args:
        name: Scraper identifier (key in the discovery map).
        cls: Scraper class to instantiate.
        limit: Optional cap on the number of records.

    Returns:
        A :class:`ScraperResult` describing the outcome.
    """
    logger.info("Running scraper %s (limit=%s)", name, limit)
    started = time.perf_counter()
    try:
        scraper = _instantiate_scraper(cls)
        applied_limit = _apply_limit(scraper, limit)
        with scraper:
            records = scraper.run()
        elapsed = time.perf_counter() - started
        logger.info(
            "Scraper %s finished in %.2fs (%d records, limit=%s)",
            name,
            elapsed,
            len(records),
            applied_limit,
        )
        return ScraperResult(
            name=name,
            elapsed_seconds=elapsed,
            records=records,
            error=None,
        )
    except Exception as exc:  # noqa: BLE001 - top-level safety net
        elapsed = time.perf_counter() - started
        logger.error(
            "Scraper %s failed after %.2fs: %s",
            name,
            elapsed,
            exc,
            exc_info=exc,
        )
        return ScraperResult(
            name=name,
            elapsed_seconds=elapsed,
            records=[],
            error=f"{type(exc).__name__}: {exc}",
        )


def run_many(
    names: Iterable[str],
    *,
    limit: Optional[int] = None,
) -> List[ScraperResult]:
    """Execute every scraper in ``names`` and return the results.

    Args:
        names: Scraper identifiers to run.
        limit: Optional cap forwarded to each scraper.

    Returns:
        A list of :class:`ScraperResult` in input order.
    """
    registry = discover_scrapers()
    results: List[ScraperResult] = []
    for name in names:
        cls = registry.get(name)
        if cls is None:
            logger.error("Unknown scraper %r (use --list to see available ones)", name)
            results.append(
                ScraperResult(
                    name=name,
                    elapsed_seconds=0.0,
                    records=[],
                    error="Unknown scraper",
                )
            )
            continue
        results.append(run_scraper(name, cls, limit=limit))
    return results


# ---------------------------------------------------------------------------
# CLI presentation
# ---------------------------------------------------------------------------


def _render_list(entries: List[ScraperEntry]) -> str:
    """Format the ``--list`` output for the terminal."""
    if not entries:
        return "No scrapers registered in backend.scrapers."
    header = (
        f"{'NAME':<20} {'CLASS':<60} {'SOURCE URL'}"
    )
    lines = [
        "Available scrapers:",
        header,
        "-" * len(header),
    ]
    for entry in entries:
        url = getattr(entry.cls, "source_url", "(unknown)") or "(unknown)"
        # Inline imports may not expose ``source_url`` as a class attribute.
        instance = _safe_instance_probe(entry.cls)
        if instance is not None and not hasattr(entry.cls, "source_url"):
            url = instance.source_url
        lines.append(f"{entry.name:<20} {entry.signature[:60]:<60} {url}")
    return "\n".join(lines)


def _safe_instance_probe(cls: Type[BaseScraper]) -> Optional[BaseScraper]:
    """Try to build a scraper instance without raising.

    Used only to read the default ``source_url`` for the ``--list``
    output. Failure is silently ignored.
    """
    try:
        return cls()
    except Exception:  # pragma: no cover - informational
        return None


def _render_results(results: List[ScraperResult]) -> str:
    """Format the per-scraper summary table."""
    lines = ["", "Per-scraper summary:", "-" * 60]
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


def _build_parser() -> argparse.ArgumentParser:
    """Construct the CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="run_scraper",
        description="Discover, list, and run ScholarBird scrapers.",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--list",
        action="store_true",
        help="List every registered scraper and exit.",
    )
    group.add_argument(
        "--scraper",
        metavar="NAME",
        help="Run a single scraper by name (see --list).",
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Run every registered scraper.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional cap on the number of records per scraper.",
    )
    return parser


def _exit_code(results: List[ScraperResult]) -> int:
    """Return ``0`` if every scraper succeeded, otherwise ``1``."""
    return 0 if all(result.ok for result in results) else 1


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point used by both ``python run_scraper.py`` and ``-m``."""
    settings = get_settings()
    configure_logging(level=settings.log_level)

    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.list:
        print(_render_list(list_scrapers()))
        return 0

    if args.scraper:
        results = run_many([args.scraper], limit=args.limit)
    elif args.all:
        registry = discover_scrapers()
        results = run_many(registry.keys(), limit=args.limit)
    else:  # pragma: no cover - mutually exclusive group guarantees one
        parser.print_help()
        return 2

    print(_render_results(results))
    if any(not result.ok for result in results):
        logger.error("One or more scrapers failed.")
    return _exit_code(results)


if __name__ == "__main__":
    raise SystemExit(main())


# ---------------------------------------------------------------------------
# Compatibility helpers (used by future unit tests)
# ---------------------------------------------------------------------------


def list_scraper_names() -> List[str]:
    """Return ``[name, ...]`` for every discovered scraper."""
    return [entry.name for entry in list_scrapers()]


def run_all(limit: Optional[int] = None) -> List[ScraperResult]:
    """Run every registered scraper (convenience for tests)."""
    return run_many(discover_scrapers().keys(), limit=limit)


def run_one(name: str, limit: Optional[int] = None) -> ScraperResult:
    """Run a single scraper by name (convenience for tests)."""
    return run_scraper(name, discover_scrapers()[name], limit=limit)


__all__ = [
    "ScraperEntry",
    "ScraperResult",
    "discover_scrapers",
    "list_scrapers",
    "list_scraper_names",
    "run_scraper",
    "run_many",
    "run_all",
    "run_one",
    "main",
]

# Re-export ``traceback`` so static analysis sees it as used (it is
# referenced in docstrings and ``logger.exception`` will include it).
_ = traceback