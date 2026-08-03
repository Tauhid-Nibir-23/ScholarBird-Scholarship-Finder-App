"""Data normalisation, validation, and deduplication.

The package exposes the normalisation, validation, and
duplicate-detection surface used by every scraper and by the
:class:`Scholarship` model.
"""

from backend.parser.normalize import (
    DEGREE_BACHELORS,
    DEGREE_MASTERS,
    DEGREE_PHD,
    DEGREE_POSTDOC,
    FUNDING_FULLY_FUNDED,
    FUNDING_PARTIALLY_FUNDED,
    FUNDING_SELF_FUNDED,
    FUNDING_UNKNOWN,
    clean_text,
    normalize_country,
    normalize_deadline,
    normalize_degree,
    normalize_funding,
    normalize_scholarship,
)
from backend.parser.validator import (
    ValidationResult,
    validate_scholarship,
)
from backend.parser.duplicate import (
    FUZZY_CANDIDATE_LIMIT,
    DuplicateDetector,
    DuplicateResult,
    DuplicateStats,
    build_duplicate_key,
    generate_content_hash,
)
from backend.parser.quality import QualityResult, assess_scholarship_quality
from backend.parser.enrich import ScholarshipEnricher

__all__ = [
    # normalisation
    "normalize_scholarship",
    "normalize_country",
    "normalize_degree",
    "normalize_funding",
    "normalize_deadline",
    "clean_text",
    # canonical constants
    "DEGREE_BACHELORS",
    "DEGREE_MASTERS",
    "DEGREE_PHD",
    "DEGREE_POSTDOC",
    "FUNDING_FULLY_FUNDED",
    "FUNDING_PARTIALLY_FUNDED",
    "FUNDING_SELF_FUNDED",
    "FUNDING_UNKNOWN",
    # validation
    "validate_scholarship",
    "ValidationResult",
    # duplicate detection
    "DuplicateDetector",
    "DuplicateResult",
    "DuplicateStats",
    "generate_content_hash",
    "build_duplicate_key",
    "FUZZY_CANDIDATE_LIMIT",
    # quality
    "QualityResult",
    "assess_scholarship_quality",
    "ScholarshipEnricher",
]
