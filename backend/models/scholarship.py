"""Strongly typed ``Scholarship`` model.

The dataclass mirrors the field set written by the existing Flutter
admin form (``lib/admin/add_scholarship_page.dart``) so records
produced by the backend stay compatible with the live mobile app.

The instance is ``frozen=True`` and therefore hashable, which is useful
for upcoming duplicate-detection logic.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from datetime import datetime
from typing import Any, Dict, List, Optional

from backend.core.exceptions import ValidationError


#: Required keys that every :class:`Scholarship` must surface.
_REQUIRED_KEYS: tuple[str, ...] = ("title", "country", "degree", "field", "deadline")


@dataclass(frozen=True)
class Scholarship:
    """Canonical representation of a scholarship record.

    Attributes:
        title: Display title shown in lists.
        country: Country the scholarship applies to.
        degree: Eligible degree level (e.g. ``"Bachelor"``).
        field: Field of study (e.g. ``"Engineering"``).
        deadline: Raw deadline string as it appears upstream. Parsers
            may normalise to ISO-8601 in a later phase.
        amount: Funding amount or human-readable funding description.
        description: Long-form description.
        link: Official scholarship URL.
        image: Optional image URL.
        min_cgpa: Optional minimum CGPA threshold.
        ielts_required: Whether IELTS is required.
        research_required: Whether research experience is required.
        source: Identifier of the scraper that produced the record.
        tags: Optional list of free-form tags.
        university: Optional institution / organisation offering the
            scholarship. Populated by scrapers that surface a
            distinct provider name distinct from the title.
        official_id: Optional upstream identifier (e.g. the SAP
            ``id`` on the DAAD database). Useful for deduplication.
        eligibility: Optional free-form eligibility text (e.g.
            applicant nationality requirements).
        apply_url: Optional direct application URL. Distinct from
            ``link`` (which is the scholarship overview page) for
            sources that expose both.
        created_at: Optional creation timestamp. Defaults to ``now``.
        updated_at: Optional last-update timestamp. Defaults to ``now``.
    """

    title: str
    country: str
    degree: str
    field: str
    deadline: str
    amount: str
    description: str
    link: str
    image: Optional[str] = None
    min_cgpa: Optional[float] = None
    cgpa_scale: float = 4.0
    max_backlogs: int = 0
    english_medium_accepted: bool = True
    fully_funded: bool = False
    ielts_required: bool = False
    research_required: bool = False
    source: str = "unknown"
    tags: List[str] = field(default_factory=list)
    university: Optional[str] = None
    official_id: Optional[str] = None
    eligibility: Optional[str] = None
    apply_url: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    # ------------------------------------------------------------------
    # Serialisation — Firestore
    # ------------------------------------------------------------------

    def to_firestore(self) -> Dict[str, Any]:
        """Return a dict matching the Flutter admin document shape.

        The returned mapping omits ``None`` values and converts
        ``datetime`` instances to ISO-8601 strings so the payload is
        JSON-serialisable from any backend context.

        Returns:
            A new dict ready for Firestore ingestion.
        """
        payload: Dict[str, Any] = {
            "title": self.title,
            "country": self.country,
            "degree": self.degree,
            "field": self.field,
            "deadline": self.deadline,
            "amount": self.amount,
            "description": self.description,
            "link": self.link,
            "fullyFunded": self.fully_funded,
            "cgpaScale": self.cgpa_scale,
            "maxBacklogs": self.max_backlogs,
            "englishMediumAccepted": self.english_medium_accepted,
            "ieltsRequired": self.ielts_required,
            "researchRequired": self.research_required,
            "isFeatured": False,
            "isHidden": False,
            "createdAt": self.created_at.isoformat(),
            "updatedAt": self.updated_at.isoformat(),
            "source": self.source,
        }
        if self.image:
            payload["image"] = self.image
        if self.min_cgpa is not None:
            payload["minCgpa"] = self.min_cgpa
        if self.tags:
            payload["tags"] = list(self.tags)
        if self.university:
            payload["university"] = self.university
        if self.official_id:
            payload["officialId"] = self.official_id
        if self.eligibility:
            payload["eligibility"] = self.eligibility
        if self.apply_url:
            payload["applyUrl"] = self.apply_url
        return payload

    @classmethod
    def from_firestore(cls, data: Dict[str, Any]) -> "Scholarship":
        """Build a :class:`Scholarship` from a Firestore document.

        Args:
            data: Raw document mapping as returned by the Firestore
                SDK. May include either ``minCgpa`` or ``minCGPA``.

        Returns:
            A populated :class:`Scholarship` instance.

        Raises:
            ValueError: If a required field is missing or empty.
        """
        required = ("title", "country", "deadline", "field")
        for key in required:
            value = data.get(key)
            if value is None or str(value).strip() == "":
                raise ValueError(f"Missing required field: {key}")

        raw_cgpa = data.get("minCgpa") or data.get("minCGPA")
        cgpa: Optional[float] = None
        if isinstance(raw_cgpa, (int, float)):
            cgpa = float(raw_cgpa)
        elif isinstance(raw_cgpa, str) and raw_cgpa.strip():
            try:
                cgpa = float(raw_cgpa)
            except ValueError:
                cgpa = None

        return cls(
            title=str(data["title"]).strip(),
            country=str(data["country"]).strip(),
            degree=str(data.get("degree", "")).strip(),
            field=str(data["field"]).strip(),
            deadline=str(data["deadline"]).strip(),
            amount=str(data.get("amount") or data.get("fundingType") or "").strip(),
            description=str(data.get("description", "")).strip(),
            link=str(data.get("link", "")).strip(),
            image=(str(data["image"]).strip() if data.get("image") else None),
            min_cgpa=cgpa,
            cgpa_scale=float(data.get("cgpaScale") or 4.0),
            max_backlogs=int(data.get("maxBacklogs") or 0),
            english_medium_accepted=bool(data.get("englishMediumAccepted", True)),
            fully_funded=bool(data.get("fullyFunded", False)),
            ielts_required=bool(data.get("ieltsRequired", False)),
            research_required=bool(data.get("researchRequired", False)),
            source=str(data.get("source", "firestore")),
            tags=[str(tag) for tag in data.get("tags", []) if tag],
            university=(str(data["university"]).strip()
                        if data.get("university") else None),
            official_id=(str(data["officialId"]).strip()
                         if data.get("officialId") else None),
            eligibility=(str(data["eligibility"]).strip()
                         if data.get("eligibility") else None),
            apply_url=(str(data["applyUrl"]).strip()
                       if data.get("applyUrl") else None),
        )

    # ------------------------------------------------------------------
    # Serialisation — generic dict
    # ------------------------------------------------------------------

    def to_dict(self) -> Dict[str, Any]:
        """Return the record as a JSON-friendly plain dict.

        ``datetime`` values are converted to ISO-8601 strings, mirroring
        :meth:`to_firestore` but without the camelCase field renaming
        or the Firestore-specific flags (``isFeatured`` / ``isHidden``).

        Returns:
            A new dict suitable for logging, CSV export, or
            ``json.dumps``.
        """
        return {
            "title": self.title,
            "country": self.country,
            "degree": self.degree,
            "field": self.field,
            "deadline": self.deadline,
            "amount": self.amount,
            "description": self.description,
            "link": self.link,
            "image": self.image,
            "min_cgpa": self.min_cgpa,
            "cgpa_scale": self.cgpa_scale,
            "max_backlogs": self.max_backlogs,
            "english_medium_accepted": self.english_medium_accepted,
            "fully_funded": self.fully_funded,
            "ielts_required": self.ielts_required,
            "research_required": self.research_required,
            "source": self.source,
            "tags": list(self.tags),
            "university": self.university,
            "official_id": self.official_id,
            "eligibility": self.eligibility,
            "apply_url": self.apply_url,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Scholarship":
        """Build a :class:`Scholarship` from a generic snake_case dict.

        This is the inverse of :meth:`to_dict`. It accepts both the
        snake_case keys produced by :meth:`to_dict` and a handful of
        common aliases (e.g. ``fundingType`` / ``amount``,
        ``minCGPA`` / ``minCgpa``) so it can ingest records from
        upstream sources as well.

        Args:
            data: Plain dict representation of a scholarship.

        Returns:
            A populated :class:`Scholarship` instance.

        Raises:
            ValueError: If a required field is missing or empty.
        """
        for key in _REQUIRED_KEYS:
            value = data.get(key)
            if value is None or str(value).strip() == "":
                raise ValueError(f"Missing required field: {key}")

        raw_cgpa = data.get("min_cgpa")
        if raw_cgpa is None:
            raw_cgpa = data.get("minCgpa")
        if raw_cgpa is None:
            raw_cgpa = data.get("minCGPA")
        cgpa: Optional[float] = None
        if isinstance(raw_cgpa, (int, float)):
            cgpa = float(raw_cgpa)
        elif isinstance(raw_cgpa, str) and raw_cgpa.strip():
            try:
                cgpa = float(raw_cgpa)
            except ValueError:
                cgpa = None

        # Parse ISO-8601 timestamps back into ``datetime`` instances so
        # ``to_dict`` -> ``from_dict`` is a lossless round-trip.
        try:
            created_at = (
                datetime.fromisoformat(data["created_at"])
                if data.get("created_at") else datetime.utcnow()
            )
        except (TypeError, ValueError):
            created_at = datetime.utcnow()
        try:
            updated_at = (
                datetime.fromisoformat(data["updated_at"])
                if data.get("updated_at") else datetime.utcnow()
            )
        except (TypeError, ValueError):
            updated_at = datetime.utcnow()

        return cls(
            title=str(data["title"]).strip(),
            country=str(data["country"]).strip(),
            degree=str(data.get("degree", "")).strip(),
            field=str(data["field"]).strip(),
            deadline=str(data["deadline"]).strip(),
            amount=str(data.get("amount") or data.get("fundingType") or "").strip(),
            description=str(data.get("description", "")).strip(),
            link=str(data.get("link", "")).strip(),
            image=(str(data["image"]).strip() if data.get("image") else None),
            min_cgpa=cgpa,
            cgpa_scale=float(data.get("cgpa_scale", data.get("cgpaScale", 4)) or 4),
            max_backlogs=int(data.get("max_backlogs", data.get("maxBacklogs", 0)) or 0),
            english_medium_accepted=bool(
                data.get("english_medium_accepted", data.get("englishMediumAccepted", True))
            ),
            fully_funded=bool(data.get("fully_funded", data.get("fullyFunded", False))),
            ielts_required=bool(data.get("ielts_required", False)),
            research_required=bool(data.get("research_required", False)),
            source=str(data.get("source", "unknown")),
            tags=[str(tag) for tag in data.get("tags", []) if tag],
            university=(str(data["university"]).strip()
                        if data.get("university") else None),
            official_id=(str(data["official_id"]).strip()
                         if data.get("official_id") else None),
            eligibility=(str(data["eligibility"]).strip()
                         if data.get("eligibility") else None),
            apply_url=(str(data["apply_url"]).strip()
                       if data.get("apply_url") else None),
            created_at=created_at,
            updated_at=updated_at,
        )

    # ------------------------------------------------------------------
    # Backwards-compatible helper
    # ------------------------------------------------------------------

    def as_dict(self) -> Dict[str, Any]:
        """Return the raw dataclass as a plain dict (debug only).

        Retained for compatibility with code written before the
        :meth:`to_dict` / :meth:`from_dict` helpers existed. Uses
        :func:`dataclasses.asdict` so ``datetime`` fields are kept as
        ``datetime`` instances (not strings).

        Returns:
            A new dict mirroring ``dataclasses.asdict``.
        """
        return asdict(self)

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def validate(self, *, raise_on_error: bool = False) -> bool:
        """Check that the record satisfies minimum quality rules.

        The implementation delegates to
        :func:`backend.parser.validator.validate_scholarship` so the
        model and the parser share one source of truth for the rule
        set. ``ValidationError`` is raised when ``raise_on_error`` is
        set and any rule fails.

        Args:
            raise_on_error: If ``True``, raise
                :class:`backend.core.exceptions.ValidationError` with
                a message describing the first failing rule. If
                ``False`` (default), return ``True`` on success and
                ``False`` on failure.

        Returns:
            ``True`` when all rules pass, otherwise ``False`` (or raise
            if ``raise_on_error`` is set).
        """
        from backend.parser.validator import validate_scholarship

        result = validate_scholarship(self.to_dict())
        if result.is_valid:
            return True
        if raise_on_error:
            raise ValidationError(
                f"Scholarship validation failed: {result.reason}"
            )
        return False

    # ------------------------------------------------------------------
    # Normalisation
    # ------------------------------------------------------------------

    def normalize(self) -> "Scholarship":
        """Return a normalised copy of this record.

        The method delegates to
        :func:`backend.parser.normalize.normalize_scholarship` so the
        rule set lives in exactly one place. Country, degree, funding,
        deadline, title, description, eligibility, university, and
        tags are rewritten; ``Scholarship`` is frozen so a new
        instance is returned with the transformed values.

        Returns:
            A new :class:`Scholarship` with normalised fields.
        """
        from backend.parser.normalize import normalize_scholarship

        snapshot = normalize_scholarship(self.to_dict())
        return Scholarship.from_dict(snapshot)

    # ------------------------------------------------------------------
    # Duplicate detection helpers
    # ------------------------------------------------------------------

    def generate_hash(self) -> str:
        """Return the canonical SHA-256 content hash for this record.

        Delegates to
        :func:`backend.parser.duplicate.generate_content_hash` so the
        hash algorithm is defined in exactly one place.

        Returns:
            64-character hex digest.
        """
        from backend.parser.duplicate import generate_content_hash

        return generate_content_hash(self.to_dict())

    def duplicate_key(self) -> Optional[str]:
        """Return the primary lookup key for duplicate detection.

        Delegates to
        :func:`backend.parser.duplicate.build_duplicate_key` so the
        priority order (``official_id`` → ``apply_url`` → ``None``)
        is shared with :class:`DuplicateDetector`.

        Returns:
            Non-empty key string, or ``None`` when neither identifier
            is available.
        """
        from backend.parser.duplicate import build_duplicate_key

        return build_duplicate_key(self.to_dict())
