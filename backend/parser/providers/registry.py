"""Dynamic discovery for every concrete :class:`ScholarshipProvider` plugin."""

from __future__ import annotations

import importlib
import inspect
import pkgutil
from typing import Optional, Type

from .base_provider import ScholarshipProvider


def _all_subclasses(base: Type[ScholarshipProvider]) -> set[Type[ScholarshipProvider]]:
    found: set[Type[ScholarshipProvider]] = set()
    pending = list(base.__subclasses__())
    while pending:
        candidate = pending.pop()
        if candidate in found:
            continue
        found.add(candidate)
        pending.extend(candidate.__subclasses__())
    return found


class ProviderRegistry:
    """Discover providers by module scan; no provider names are hardcoded."""

    def __init__(self) -> None:
        self._types: dict[str, Type[ScholarshipProvider]] = {}

    @classmethod
    def discover(cls, package: str = "backend.parser.providers") -> "ProviderRegistry":
        registry = cls()
        module = importlib.import_module(package)
        package_path = getattr(module, "__path__", ())
        for item in pkgutil.iter_modules(package_path):
            if not item.name.startswith("_"):
                importlib.import_module(f"{package}.{item.name}")
        for provider_type in _all_subclasses(ScholarshipProvider):
            if inspect.isabstract(provider_type) or provider_type is ScholarshipProvider:
                continue
            name = str(getattr(provider_type, "name", "")).strip()
            if name and name != "generic":
                registry._types[name] = provider_type
        return registry

    def provider_types(self) -> tuple[Type[ScholarshipProvider], ...]:
        return tuple(self._types[name] for name in sorted(self._types))

    def providers(self) -> tuple[ScholarshipProvider, ...]:
        return tuple(provider_type() for provider_type in self.provider_types())

    def detect(self, *, source: str, url: str, official_id: Optional[str] = None) -> Optional[ScholarshipProvider]:
        for provider in self.providers():
            if provider.matches(source=source, url=url, official_id=official_id):
                return provider
        return None


def detect_provider(*, source: str, url: str, official_id: Optional[str] = None) -> Optional[ScholarshipProvider]:
    """Dynamically discover providers and return the one matching this record."""
    return ProviderRegistry.discover().detect(source=source, url=url, official_id=official_id)


__all__ = ["ProviderRegistry", "detect_provider"]
