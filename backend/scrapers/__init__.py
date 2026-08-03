"""Scraper package.

This package exposes:

* :class:`BaseScraper` — the abstract interface every concrete scraper
  inherits from.
* :class:`ScraperRegistry` and :class:`ScraperEntry` — the plugin
  registry that lets the orchestrator pick up new scrapers without
  edits to :mod:`backend.main`.
"""

from backend.scrapers.base_scraper import BaseScraper
from backend.scrapers.registry import ScraperEntry, ScraperRegistry

__all__ = ["BaseScraper", "ScraperEntry", "ScraperRegistry"]