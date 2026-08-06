"""Production extraction engine for ScholarBird.

This package is *additive*. It augments ``backend.parser.enrich`` with
deterministic, priority-ordered extraction of every field on the
:mod:`models.scholarship` dataclass without touching any existing
module. The engines never infer or invent values — every slot is
populated only when the source page provides explicit evidence.

Public API
----------

* :class:`FetchedPage` — a network-fetched page ready for extraction.
* :class:`ExtractedFields` — the canonical result shape.
* :class:`FieldExtractor` — top-level orchestrator implementing the
  10-step priority order described in the project documentation.
* :func:`extract_fields_from_html` — short-hand wrapper around the
  above plus an optional merge into an existing dict.

Per-field helpers (used internally and exposed for direct testing):

* :func:`parser.extractors.deadline.extract_deadline`
* :func:`parser.extractors.degree.extract_degree`
* :func:`parser.extractors.description.clean_description`
* :func:`parser.extractors.field.extract_field`
* :func:`parser.extractors.funding.extract_funding`
* :func:`parser.extractors.html.extract_text` / ``extract_meta`` /
  ``find_section`` etc.
* :func:`parser.extractors.image.extract_images`
* :func:`parser.extractors.jsonld.extract_jsonld`
* :func:`parser.extractors.metadata.extract_metadata`
* :func:`parser.extractors.opengraph.extract_opengraph`
* :func:`parser.extractors.requirements.extract_requirements`
* :func:`parser.extractors.university.extract_university`
"""

from __future__ import annotations

from .engine import (
    ExtractedFields,
    FetchedPage,
    FieldExtractor,
    extract_fields_from_html,
)
from .image_robust import (
    HERO_CLASS_TOKENS,
    RobustImageResult,
    extract_robust_images,
    pick_best as pick_best_image,
)


__all__ = [
    "ExtractedFields",
    "FetchedPage",
    "FieldExtractor",
    "HERO_CLASS_TOKENS",
    "RobustImageResult",
    "extract_fields_from_html",
    "extract_robust_images",
    "pick_best_image",
]
