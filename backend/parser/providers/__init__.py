"""Source-specific, additive scholarship extraction plugins."""

from .base_provider import ProviderExtraction, ScholarshipProvider
from .registry import ProviderRegistry, detect_provider
from .chevening import CheveningProvider
from .daad import DaadProvider

__all__ = [
    "CheveningProvider",
    "DaadProvider",
    "ProviderExtraction",
    "ProviderRegistry",
    "ScholarshipProvider",
    "detect_provider",
]
