"""Data models for the ScholarBird backend.

Models are pure dataclasses without I/O. They describe the shape of
records flowing between scrapers, parsers, and the Firestore writer.
"""

from backend.models.scholarship import Scholarship

__all__ = ["Scholarship"]
