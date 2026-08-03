"""Production scheduler for the existing registry-based scraper pipeline."""

from __future__ import annotations

import argparse
import sys
import threading
import time
from datetime import datetime, timezone
from typing import Any, Callable, Optional

from backend.config.settings import Settings, get_settings
from backend.core.logger import configure_logging, get_logger
from backend.orchestrator import ScraperOrchestrator

_logger = get_logger(__name__)
PipelineRunner = Callable[[], Any]


class ScraperScheduler:
    """Run the existing orchestrator on an environment-configured interval."""

    def __init__(
        self,
        settings: Optional[Settings] = None,
        *,
        runner: Optional[PipelineRunner] = None,
    ) -> None:
        self.settings = settings or get_settings()
        self._runner = runner or self._run_orchestrator
        self._lock = threading.Lock()
        self._scheduler: Any = None
        self.last_execution: Optional[datetime] = None
        self.last_upload_summary: Optional[dict[str, Any]] = None

    @property
    def running(self) -> bool:
        return bool(self._scheduler and self._scheduler.running)

    @staticmethod
    def _run_orchestrator() -> Any:
        return ScraperOrchestrator().run()

    def run_once(self) -> Optional[dict[str, Any]]:
        """Run the existing pipeline once, skipping an overlapping invocation."""
        if not self._lock.acquire(blocking=False):
            _logger.warning("Scheduled scraper execution skipped: run already active")
            return None

        started = time.perf_counter()
        self.last_execution = datetime.now(timezone.utc)
        _logger.info("Scheduled scraper execution started")
        try:
            result = self._runner()
            summary = result.as_dict() if hasattr(result, "as_dict") else dict(result)
            self.last_upload_summary = summary
            _logger.info(
                "Scheduled scraper execution finished: new=%s updated=%s "
                "skipped=%s failed=%s execution_time=%.3fs",
                summary.get("total_new", summary.get("new", 0)),
                summary.get("total_updated", summary.get("updated", 0)),
                summary.get("total_skipped", summary.get("skipped", 0)),
                summary.get("total_failed", summary.get("failed", 0)),
                time.perf_counter() - started,
            )
            return summary
        except Exception:
            _logger.exception(
                "Scheduled scraper execution failed after %.3fs",
                time.perf_counter() - started,
            )
            raise
        finally:
            self._lock.release()

    def start(self, *, block: bool = True) -> bool:
        """Start interval scheduling when enabled by ``SCRAPER_ENABLED``."""
        if not self.settings.scraper_enabled:
            _logger.info("Scheduler disabled by SCRAPER_ENABLED")
            return False

        try:
            from apscheduler.schedulers.background import BackgroundScheduler
            from apscheduler.schedulers.blocking import BlockingScheduler
        except ImportError as exc:  # pragma: no cover - deployment guard
            raise RuntimeError("APScheduler is required to start the scheduler") from exc

        scheduler_type = BlockingScheduler if block else BackgroundScheduler
        self._scheduler = scheduler_type(timezone="UTC")
        self._scheduler.add_job(
            self.run_once,
            trigger="interval",
            hours=self.settings.scraper_interval_hours,
            id="scholarbird-scraper",
            replace_existing=True,
            coalesce=True,
            max_instances=1,
        )
        _logger.info(
            "Scheduler started (interval_hours=%d)",
            self.settings.scraper_interval_hours,
        )
        self._scheduler.start()
        return True

    def shutdown(self) -> None:
        if self.running:
            self._scheduler.shutdown(wait=False)


def main(argv: Optional[list[str]] = None) -> int:
    # The existing orchestrator emits Unicode status markers. Windows service
    # consoles may use cp1252, so replace unsupported glyphs rather than
    # aborting a scheduled production run before scraping begins.
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(errors="replace")

    parser = argparse.ArgumentParser(description="Run ScholarBird production scheduling.")
    parser.add_argument("--once", action="store_true", help="Run the existing orchestrator once.")
    args = parser.parse_args(argv)
    settings = get_settings()
    configure_logging(level=settings.log_level)
    scheduler = ScraperScheduler(settings)
    if args.once:
        scheduler.run_once()
        return 0
    scheduler.start(block=True)
    return 0


if __name__ == "__main__":  # pragma: no cover - manual process entry point
    raise SystemExit(main())
