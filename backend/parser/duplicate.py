"""Production-grade duplicate detection for scholarship records.

The detector answers the question *“is this record the same scholarship we
have already stored?”* using a layered strategy that scales to 10,000+
records without quadratic blow-up:

1. **Primary lookup** — O(1) dictionary lookups keyed by ``official_id``,
   ``apply_url``, or a SHA-256 *content hash* over the canonical fields
   ``title + country + degree + university + source``.
2. **Secondary lookup** — when the primary keys miss, RapidFuzz is used
   to compare the ``title + university`` combination against every
   candidate whose content hash is unknown. Comparison is capped at
   :data:`FUZZY_CANDIDATE_LIMIT` entries to keep the worst case
   bounded.
3. **Statistics** — every call updates counters so the caller can
   monitor ``new``, ``duplicate``, ``updated`` and ``ignored``
   outcomes.

The module exposes:

* :class:`DuplicateResult` — frozen dataclass describing a single
  comparison outcome.
* :class:`DuplicateDetector` — stateful tracker that maintains the
  in-memory index.
* :func:`generate_content_hash` — stateless helper that produces the
  canonical SHA-256 fingerprint. The :class:`Scholarship` model
  delegates here for ``generate_hash()`` so there is only one source of
  truth.
* :func:`build_duplicate_key` — stateless helper that returns the
  primary key (``official_id`` → ``apply_url`` → ``None``).

The detector never raises on a duplicate; it always returns a
:class:`DuplicateResult` describing the match.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional

from rapidfuzz import fuzz

from backend.core.logger import get_logger

_logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Public constants — match threshold + candidate cap
# ---------------------------------------------------------------------------

#: Similarity threshold (0–100) above which the fuzzy stage reports a
#: duplicate.
FUZZY_THRESHOLD: int = 90

#: Hard cap on fuzzy comparisons per incoming record. The cap bounds
#: the worst-case runtime of the secondary stage; when more candidates:
#: exist, only the first ``FUZZY_CANDIDATE_LIMIT`` are scanned.
FUZZY_CANDIDATE_LIMIT: int = 5000

#: Fields that contribute to the SHA-256 content hash. Order matters —
#: it is part of the canonical form.
_HASH_FIELDS: tuple[str, ...] = (
    "title",
    "country",
    "degree",
    "university",
    "source",
)

#: Fields that participate in the fuzzy comparison alongside the title.
_FUZZY_FIELDS: tuple[str, ...] = (
    "title",
    "university",
)

#: Pre-compiled whitespace stripper — used to build stable hash inputs
#: regardless of how the upstream source formatted the values.
_WHITESPACE_RE = re.compile(r"\s+")


# ---------------------------------------------------------------------------
# Pure helpers — exposed so the Scholarship model can delegate to them
# ---------------------------------------------------------------------------

def _canonicalise(value: Any) -> str:
    """Return ``value`` normalised into a stable string for hashing.

    ``None`` becomes the empty string. Everything else is stripped,
    lower-cased, and collapsed onto single spaces. The transformation
    is intentionally lossy: ``"MIT"`` and ``"mit"`` must collide.

    Args:
        value: Any value coming from a scholarship field.

    Returns:
        A canonical string suitable for joining into a hash input.
    """
    if value is None:
        return ""
    text = str(value).strip().lower()
    text = _WHITESPACE_RE.sub(" ", text)
    return text


def generate_content_hash(record: Dict[str, Any]) -> str:
    """Compute the canonical SHA-256 fingerprint of ``record``.

    The hash input is the ``"|"``-joined canonical form of
    :data:`_HASH_FIELDS`. Identical scholarship content produces the
    same hash regardless of casing or whitespace variation in the
    source fields.

    Args:
        record: Mapping with at least ``title``, ``country``,
            ``degree``, ``university``, ``source``.

    Returns:
        64-character hex digest.
    """
    parts = [_canonicalise(record.get(name)) for name in _HASH_FIELDS]
    payload = "|".join(parts).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def build_duplicate_key(record: Dict[str, Any]) -> Optional[str]:
    """Return the primary lookup key for ``record``.

    Priority:

    1. ``official_id`` (when non-empty).
    2. ``apply_url`` (when non-empty).
    3. ``None`` — caller should fall through to the content-hash
       stage.

    Args:
        record: Mapping representing a scholarship.

    Returns:
        A non-empty string or ``None``.
    """
    official_id = record.get("official_id")
    if official_id is not None:
        text = str(official_id).strip()
        if text:
            return f"official_id::{text}"

    apply_url = record.get("apply_url")
    if apply_url is not None:
        text = str(apply_url).strip()
        if text:
            return f"apply_url::{text}"

    return None


# ---------------------------------------------------------------------------
# Result dataclass
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DuplicateResult:
    """Outcome of comparing one record against the detector index.

    Attributes:
        is_duplicate: ``True`` when the record matched something
            already known.
        matched_by: One of ``"official_id"``, ``"apply_url"``,
            ``"content_hash"``, ``"fuzzy"`` or ``"none"``.
        matched_document: The record that triggered the match, or
            ``None`` when :attr:`is_duplicate` is ``False``.
        confidence: Match confidence in the inclusive range
            ``0.0 – 1.0``. ``1.0`` for exact primary matches;
            fuzzy matches report the normalised RapidFuzz score.
    """

    is_duplicate: bool
    matched_by: str = "none"
    matched_document: Optional[Dict[str, Any]] = None
    confidence: float = 0.0

    def __bool__(self) -> bool:  # pragma: no cover - convenience
        """Allow ``if detector.check(record):`` usage."""
        return self.is_duplicate


# ---------------------------------------------------------------------------
# Detector
# ---------------------------------------------------------------------------

@dataclass
class DuplicateStats:
    """Counters describing the detector's run so far.

    Attributes:
        new_records: Records the detector identified as new.
        duplicate_records: Records that matched an existing entry.
        updated_records: Records that updated an existing entry
            (currently only tracked when ``mark_updated=True`` is
            passed to :meth:`DuplicateDetector.ingest`).
        ignored_records: Records that the caller asked to skip
            (``mark_ignored=True``).
    """

    new_records: int = 0
    duplicate_records: int = 0
    updated_records: int = 0
    ignored_records: int = 0

    def as_dict(self) -> Dict[str, int]:
        """Return a plain dict copy of the counters."""
        return {
            "new_records": self.new_records,
            "duplicate_records": self.duplicate_records,
            "updated_records": self.updated_records,
            "ignored_records": self.ignored_records,
        }


class DuplicateDetector:
    """Stateful duplicate tracker with O(1) primary lookups.

    The detector holds three parallel indexes:

    * ``_primary`` — keyed by :func:`build_duplicate_key` output
      (``official_id`` or ``apply_url``).
    * ``_hash_index`` — keyed by :func:`generate_content_hash` output.
    * ``_candidates`` — list of records that *only* have a fuzzy
      signature (i.e. no primary key and a stable title + university).

    All indexes are kept in sync via :meth:`remember` /
    :meth:`ingest`.

    Typical usage::

        detector = DuplicateDetector()
        for raw in scraper.fetch():
            normalised = normalize_scholarship(raw)
            result = detector.check(normalised)
            if result.is_duplicate:
                continue
            detector.remember(normalised)
            save_to_firestore(normalised)

    Args:
        fuzzy_threshold: Similarity threshold in the range
            ``0–100``. Defaults to :data:`FUZZY_THRESHOLD`.
        fuzzy_candidate_limit: Maximum number of fuzzy candidates the
            secondary stage will scan per call. Defaults to
            :data:`FUZZY_CANDIDATE_LIMIT`.
    """

    def __init__(
        self,
        *,
        fuzzy_threshold: int = FUZZY_THRESHOLD,
        fuzzy_candidate_limit: int = FUZZY_CANDIDATE_LIMIT,
    ) -> None:
        """Initialise an empty detector."""
        if not 0 <= fuzzy_threshold <= 100:
            raise ValueError("fuzzy_threshold must be between 0 and 100")
        if fuzzy_candidate_limit <= 0:
            raise ValueError("fuzzy_candidate_limit must be positive")

        self._fuzzy_threshold: int = fuzzy_threshold
        self._fuzzy_candidate_limit: int = fuzzy_candidate_limit

        # primary keys (official_id / apply_url) → record
        self._primary: Dict[str, Dict[str, Any]] = {}
        # content hash → record
        self._hash_index: Dict[str, Dict[str, Any]] = {}
        # records that have no primary key — used for fuzzy matching
        self._candidates: List[Dict[str, Any]] = []
        # fuzzy signature for each candidate (title + university)
        self._candidate_sigs: List[str] = []

        self.stats: DuplicateStats = DuplicateStats()
        _logger.debug(
            "DuplicateDetector initialised (threshold=%d, cap=%d)",
            fuzzy_threshold,
            fuzzy_candidate_limit,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check(self, record: Dict[str, Any]) -> DuplicateResult:
        """Compare ``record`` against everything currently indexed.

        The check runs in priority order:

        1. :func:`build_duplicate_key` lookup.
        2. :func:`generate_content_hash` lookup.
        3. Fuzzy match over :attr:`_candidates`, bounded by
           ``fuzzy_candidate_limit``.

        Args:
            record: Mapping to compare.

        Returns:
            A :class:`DuplicateResult`. ``result.is_duplicate`` is
            ``False`` when nothing matched.
        """
        primary_key = build_duplicate_key(record)
        if primary_key is not None and primary_key in self._primary:
            return DuplicateResult(
                is_duplicate=True,
                matched_by=(
                    "official_id"
                    if primary_key.startswith("official_id::")
                    else "apply_url"
                ),
                matched_document=self._primary[primary_key],
                confidence=1.0,
            )

        content_hash = generate_content_hash(record)
        if content_hash in self._hash_index:
            return DuplicateResult(
                is_duplicate=True,
                matched_by="content_hash",
                matched_document=self._hash_index[content_hash],
                confidence=1.0,
            )

        fuzzy_match = self._fuzzy_search(record, content_hash)
        if fuzzy_match is not None:
            matched_doc, score = fuzzy_match
            return DuplicateResult(
                is_duplicate=True,
                matched_by="fuzzy",
                matched_document=matched_doc,
                confidence=round(score / 100.0, 4),
            )

        return DuplicateResult(is_duplicate=False)

    def remember(self, record: Dict[str, Any]) -> None:
        """Add ``record`` to the in-memory indexes.

        Safe to call multiple times with the same record — duplicate
        indexes simply overwrite the previous entry. Callers usually
        pair this with :meth:`check` to avoid inserting duplicates.

        Args:
            record: Mapping representing a scholarship.
        """
        # Index under every available primary key so a future record
        # that shares *any* primary identifier still resolves, even
        # when the indexed record was loaded with both fields.
        for key in self._iter_primary_keys(record):
            self._primary[key] = record

        content_hash = generate_content_hash(record)
        self._hash_index[content_hash] = record

        # Maintain a fuzzy candidate list. Records that already have a
        # primary key are still indexed fuzzily as a safety net: if an
        # upstream source omits both identifiers, the fuzzy stage
        # still has a chance to catch the duplicate.
        if self._has_fuzzy_signature(record):
            self._candidates.append(record)
            self._candidate_sigs.append(self._fuzzy_signature(record))

    def forget(self, record: Dict[str, Any]) -> None:
        """Remove ``record`` from all indexes (used by tests).

        Args:
            record: Mapping previously passed to :meth:`remember`.
        """
        for key in self._iter_primary_keys(record):
            if self._primary.get(key) is record:
                self._primary.pop(key, None)

        content_hash = generate_content_hash(record)
        if self._hash_index.get(content_hash) is record:
            self._hash_index.pop(content_hash, None)

        if self._has_fuzzy_signature(record):
            signature = self._fuzzy_signature(record)
            for index, (candidate, candidate_sig) in enumerate(
                zip(self._candidates, self._candidate_sigs)
            ):
                if candidate is record and candidate_sig == signature:
                    self._candidates.pop(index)
                    self._candidate_sigs.pop(index)
                    break

    @staticmethod
    def _iter_primary_keys(record: Dict[str, Any]) -> Iterable[str]:
        """Yield every primary key available on ``record``.

        Yields:
            The ``"official_id::..."`` key when ``official_id`` is
            non-empty, followed by the ``"apply_url::..."`` key when
            ``apply_url`` is non-empty. The order matches the
            priority used by :meth:`check` so debugging logs are
            predictable.
        """
        official_id = record.get("official_id")
        if official_id is not None:
            text = str(official_id).strip()
            if text:
                yield f"official_id::{text}"
        apply_url = record.get("apply_url")
        if apply_url is not None:
            text = str(apply_url).strip()
            if text:
                yield f"apply_url::{text}"

    def reset(self) -> None:
        """Clear every index and reset the statistics counters."""
        self._primary.clear()
        self._hash_index.clear()
        self._candidates.clear()
        self._candidate_sigs.clear()
        self.stats = DuplicateStats()

    def bulk_load(self, records: Iterable[Dict[str, Any]]) -> None:
        """Seed the indexes with a batch of pre-existing records.

        Useful when the detector is constructed after a Firestore
        pull — every existing record is registered so the next ingest
        immediately recognises duplicates.

        Args:
            records: Iterable of pre-existing scholarships.
        """
        for record in records:
            self.remember(record)

    def ingest(
        self,
        record: Dict[str, Any],
        *,
        mark_updated: bool = False,
        mark_ignored: bool = False,
    ) -> DuplicateResult:
        """Run :meth:`check` and update statistics in one call.

        When ``record`` is new, the detector indexes it automatically
        via :meth:`remember`. When it is a duplicate, the caller
        receives a :class:`DuplicateResult` and the indexes are left
        untouched.

        Args:
            record: Mapping representing a scholarship.
            mark_updated: When ``True``, increment
                ``stats.updated_records`` instead of
                ``stats.duplicate_records``. Use this when the caller
                intends to overwrite the existing entry.
            mark_ignored: When ``True``, increment
                ``stats.ignored_records``. Useful for records the
                caller chose to discard for downstream reasons.

        Returns:
            The :class:`DuplicateResult` from the primary check.
        """
        if mark_ignored:
            self.stats.ignored_records += 1
            return DuplicateResult(is_duplicate=False)

        result = self.check(record)
        if result.is_duplicate:
            if mark_updated:
                self.stats.updated_records += 1
            else:
                self.stats.duplicate_records += 1
            return result

        self.remember(record)
        self.stats.new_records += 1
        return result

    # ------------------------------------------------------------------
    # Diagnostics
    # ------------------------------------------------------------------

    def __len__(self) -> int:
        """Return the number of distinct records currently indexed."""
        return len(self._hash_index)

    @property
    def seen_hashes(self) -> set:
        """Return a snapshot of every content hash currently indexed.

        Exposed so collaborating modules (the Firestore uploader,
        pipeline glue) can decide whether a given hash has already
        been registered in this run without poking at private
        attributes. The returned set is a copy; mutating it has no
        effect on the detector.
        """
        return set(self._hash_index.keys())

    @property
    def fuzzy_threshold(self) -> int:
        """Return the active similarity threshold (0–100)."""
        return self._fuzzy_threshold

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _has_fuzzy_signature(record: Dict[str, Any]) -> bool:
        """Return ``True`` when ``record`` has a usable title/university."""
        title = _canonicalise(record.get("title"))
        if not title:
            return False
        return True

    @staticmethod
    def _fuzzy_signature(record: Dict[str, Any]) -> str:
        """Return the canonical text used by the fuzzy stage."""
        title = _canonicalise(record.get("title"))
        university = _canonicalise(record.get("university"))
        return f"{title} :: {university}" if university else title

    def _fuzzy_search(
        self,
        record: Dict[str, Any],
        content_hash: str,
    ) -> Optional[tuple[Dict[str, Any], float]]:
        """Scan candidates with RapidFuzz, returning the best match.

        Args:
            record: Incoming record.
            content_hash: Hash of ``record``; same-hash matches are
                already handled by the primary stage, so the fuzzy
                stage skips them implicitly (different hashes imply
                different content).

        Returns:
            ``(matched_record, score)`` when the best score meets
            :attr:`_fuzzy_threshold`, otherwise ``None``.
        """
        if not self._candidate_sigs:
            return None
        if not self._has_fuzzy_signature(record):
            return None

        target_title = _canonicalise(record.get("title"))
        target_university = _canonicalise(record.get("university"))
        if not target_title:
            return None

        cap = min(len(self._candidate_sigs), self._fuzzy_candidate_limit)
        # The candidate signature is already ``"<title> :: <university>"``;
        # comparing with the same shape (using ``fuzz.ratio``) ensures
        # the university token contributes to the similarity score, so
        # two records with the same title but different universities do
        # not collide.
        target_combined = (
            f"{target_title} :: {target_university}" if target_university
            else target_title
        )

        best_score = 0.0
        best_index = -1
        for index, candidate_sig in enumerate(self._candidate_sigs[:cap]):
            score = fuzz.ratio(target_combined, candidate_sig)
            if score > best_score:
                best_score = score
                best_index = index

        if best_score < self._fuzzy_threshold or best_index < 0:
            return None

        matched_doc = self._candidates[best_index]
        # Defence-in-depth: same content hash already handled by the
        # hash stage, but skip it here too.
        if generate_content_hash(matched_doc) == content_hash:
            return None
        return matched_doc, best_score


__all__ = [
    "DuplicateDetector",
    "DuplicateResult",
    "DuplicateStats",
    "FUZZY_THRESHOLD",
    "FUZZY_CANDIDATE_LIMIT",
    "build_duplicate_key",
    "generate_content_hash",
]