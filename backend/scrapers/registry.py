"""Plugin registry for ScholarBird scrapers.

The :class:`ScraperRegistry` is the single source of truth for "which
scrapers exist" in the running process. New scrapers are added by
**dropping a new module under** :mod:`backend.scrapers` and
implementing a :class:`BaseScraper` subclass — no edits to
:mod:`backend.main` or any other file are required.

Design
------

* :meth:`ScraperRegistry.register` accepts either a class (preferred)
  or a fully-constructed instance. Passing a class is the contract used
  by :meth:`ScraperRegistry.discover`.
* :meth:`ScraperRegistry.unregister` accepts the class, the instance,
  or the scraper ``name`` and removes the entry from the registry.
* :meth:`ScraperRegistry.list` returns a snapshot of the registered
  entries in deterministic order so log lines and console output are
  reproducible.
* :meth:`ScraperRegistry.discover` walks the :mod:`backend.scrapers`
  package, imports every module, and harvests concrete
  :class:`BaseScraper` subclasses. The discovery step is idempotent —
  calling it repeatedly never duplicates entries.

Performance
-----------

* Importing a module is cached by Python, so subsequent ``discover()``
  calls are O(number-of-modules) without re-importing anything.
* The registry holds classes, **not** instances — instantiation is
  deferred to the orchestrator, which can then create one per worker
  thread when running in parallel.
* No HTTP clients, no Firebase handles, and no settings lookups are
  performed at registration time. That keeps the registry safe to
  import in environments where Firebase credentials are absent (e.g.
  the unit-test suite).
"""

from __future__ import annotations

import importlib
import inspect
import pkgutil
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Type, Union

from backend.core.logger import get_logger
from backend.scrapers.base_scraper import BaseScraper

_logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Public dataclass
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ScraperEntry:
    """Description of a registered scraper.

    Attributes:
        name: Stable lowercase identifier (matches
            :attr:`BaseScraper.name`).
        cls: The scraper class itself — the orchestrator instantiates
            it on demand.
        module: Dotted module path where the class was defined.
    """

    name: str
    cls: Type[BaseScraper]
    module: str

    def __str__(self) -> str:  # pragma: no cover - formatting helper
        return f"{self.name:<20} {self.cls.__module__}.{self.cls.__name__}"


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------


class ScraperRegistry:
    """In-memory catalogue of available scrapers.

    The registry is intentionally tiny — a mapping keyed by scraper
    ``name``. Public methods are thread-safe only at the granularity
    Python's GIL provides, which is sufficient for the orchestrator's
    "load-once, read-many" pattern.

    Examples:
        Basic registration::

            registry = ScraperRegistry()
            registry.register(DaadScraper)
            assert registry.get("daad") is DaadScraper

        Automatic discovery::

            registry = ScraperRegistry.discover()
            names = registry.list()
    """

    def __init__(self) -> None:
        """Initialise an empty registry."""
        self._entries: Dict[str, ScraperEntry] = {}

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    def register(
        self,
        scraper: Union[Type[BaseScraper], BaseScraper],
    ) -> ScraperEntry:
        """Register a scraper class or instance.

        Args:
            scraper: Either a :class:`BaseScraper` **subclass** or an
                already-instantiated scraper object. Instances are
                unwrapped to their class so the registry only ever
                stores classes.

        Returns:
            The :class:`ScraperEntry` that was added to (or refreshed
            in) the registry.

        Raises:
            TypeError: When ``scraper`` is neither a class nor an
                instance of :class:`BaseScraper`.
        """
        cls = self._coerce_to_class(scraper)
        if not self._is_concrete(cls):
            raise TypeError(
                f"Cannot register {cls!r}: must be a concrete "
                f"subclass of BaseScraper."
            )

        name = self._resolve_name(cls)
        entry = ScraperEntry(
            name=name,
            cls=cls,
            module=cls.__module__ or cls.__qualname__,
        )
        self._entries[name] = entry
        _logger.debug(
            "ScraperRegistry: registered %s -> %s.%s",
            name,
            entry.module,
            cls.__name__,
        )
        return entry

    def unregister(
        self,
        target: Union[str, Type[BaseScraper], BaseScraper],
    ) -> Optional[ScraperEntry]:
        """Remove a scraper from the registry.

        Args:
            target: Either the scraper ``name`` (str), the class, or
                an instance. Strings are matched against
                :attr:`BaseScraper.name`; classes and instances are
                matched by identity (``is``).

        Returns:
            The removed :class:`ScraperEntry`, or ``None`` when no
            match was found.
        """
        if isinstance(target, str):
            entry = self._entries.pop(target, None)
            if entry is not None:
                _logger.debug("ScraperRegistry: unregistered %s", target)
            return entry

        cls = self._coerce_to_class(target)
        name = self._resolve_name(cls)
        if name in self._entries and self._entries[name].cls is cls:
            entry = self._entries.pop(name)
            _logger.debug(
                "ScraperRegistry: unregistered %s (class match)", name
            )
            return entry

        # Fall back to scanning entries so an instance with an unusual
        # ``name`` attribute is still removed cleanly.
        for candidate_name, candidate_entry in list(self._entries.items()):
            if candidate_entry.cls is cls:
                return self._entries.pop(candidate_name)
        return None

    def list(self) -> List[ScraperEntry]:
        """Return a deterministic list of registered entries.

        The list is sorted by scraper ``name`` so console output stays
        stable across runs.

        Returns:
            A new list of :class:`ScraperEntry` instances. Mutating
            the list has no effect on the registry.
        """
        return [self._entries[name] for name in sorted(self._entries)]

    def names(self) -> List[str]:
        """Return the sorted list of registered scraper names.

        Returns:
            A new list of strings.
        """
        return sorted(self._entries)

    def get(self, name: str) -> Optional[ScraperEntry]:
        """Return the entry for ``name`` or ``None`` when absent."""
        return self._entries.get(name)

    def __contains__(self, name: str) -> bool:
        return name in self._entries

    def __len__(self) -> int:
        return len(self._entries)

    def __iter__(self):  # type: ignore[no-untyped-def]
        """Iterate over :class:`ScraperEntry` instances in name order."""
        return iter(self.list())

    def clear(self) -> None:
        """Remove every registered entry."""
        self._entries.clear()

    # ------------------------------------------------------------------
    # Discovery
    # ------------------------------------------------------------------

    @classmethod
    def discover(
        cls,
        *,
        package: str = "backend.scrapers",
        only: Optional[Iterable[str]] = None,
        skip: Optional[Iterable[str]] = None,
    ) -> "ScraperRegistry":
        """Build a registry by walking ``package`` and harvesting subclasses.

        The discovery process:

        1. Import :mod:`backend.scrapers` (or the supplied override).
        2. For every module under that package — except ones whose
           name starts with ``_`` — import it and inspect its classes.
        3. Collect concrete :class:`BaseScraper` subclasses, ignoring
           classes that are re-exported from elsewhere.

        Args:
            package: Dotted import path to the package to scan.
            only: Optional iterable of scraper names to keep. When
                provided, names not in the iterable are dropped from
                the resulting registry.
            skip: Optional iterable of scraper names to ignore.
                Useful for tests that want to load everything except
                the network-bound production scraper.

        Returns:
            A populated :class:`ScraperRegistry`.
        """
        registry = cls()
        importlib.import_module(package)
        package_module = importlib.import_module(package)
        package_path = getattr(package_module, "__path__", None)
        if not package_path:
            _logger.warning(
                "ScraperRegistry.discover: %s has no __path__; nothing to scan",
                package,
            )
            return registry

        only_set = set(only) if only is not None else None
        skip_set = set(skip) if skip is not None else set()

        for module_info in pkgutil.iter_modules(package_path):
            if module_info.name.startswith("_"):
                continue
            module = importlib.import_module(f"{package}.{module_info.name}")
            for _, obj in inspect.getmembers(module, inspect.isclass):
                if obj.__module__ != module.__name__:
                    continue  # skip re-exports
                if not cls._is_concrete(obj):
                    continue
                name = cls._resolve_name(obj)
                if only_set is not None and name not in only_set:
                    continue
                if name in skip_set:
                    continue
                registry.register(obj)
        _logger.info(
            "ScraperRegistry.discover: registered %d scraper(s) from %s",
            len(registry),
            package,
        )
        return registry

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    @staticmethod
    def _coerce_to_class(
        scraper: Union[Type[BaseScraper], BaseScraper],
    ) -> Type[BaseScraper]:
        """Return the class behind ``scraper``.

        Args:
            scraper: Class or instance.

        Returns:
            The corresponding :class:`BaseScraper` subclass.

        Raises:
            TypeError: When ``scraper`` is neither a class nor a
                :class:`BaseScraper` instance.
        """
        if inspect.isclass(scraper):
            if not issubclass(scraper, BaseScraper):
                raise TypeError(
                    f"{scraper!r} is not a subclass of BaseScraper."
                )
            return scraper
        if isinstance(scraper, BaseScraper):
            return type(scraper)
        raise TypeError(
            f"Expected BaseScraper class or instance, got {type(scraper).__name__}."
        )

    @staticmethod
    def _is_concrete(cls: type) -> bool:
        """Return ``True`` when ``cls`` is a concrete :class:`BaseScraper`."""
        if not isinstance(cls, type):
            return False
        if cls is BaseScraper:
            return False
        if not issubclass(cls, BaseScraper):
            return False
        return not inspect.isabstract(cls)

    @staticmethod
    def _resolve_name(cls: Type[BaseScraper]) -> str:
        """Return the registry key for ``cls``.

        Priority:
        1. :attr:`BaseScraper.name` when it is a non-empty string.
        2. The lower-cased class name as a deterministic fallback.
        """
        candidate = getattr(cls, "name", None)
        if isinstance(candidate, str) and candidate.strip():
            return candidate.strip()
        return cls.__name__.lower()


__all__ = ["ScraperEntry", "ScraperRegistry"]
