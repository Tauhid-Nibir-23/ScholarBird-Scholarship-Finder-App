"""Configuration package for the ScholarBird backend.

This package centralises access to runtime settings and project-wide
constants. Importing the submodules has no side effects and never
initialises any third-party SDK.
"""

from backend.config.settings import Settings, get_settings
from backend.config.constants import (
    APP_NAME,
    APP_VERSION,
    DEFAULT_LOG_LEVEL,
    LOG_FORMAT,
)

__all__ = [
    "Settings",
    "get_settings",
    "APP_NAME",
    "APP_VERSION",
    "DEFAULT_LOG_LEVEL",
    "LOG_FORMAT",
]
