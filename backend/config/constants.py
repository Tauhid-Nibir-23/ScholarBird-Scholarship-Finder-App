"""Project-wide constants for the ScholarBird backend.

Constants here are intentionally static. Anything that may vary between
deployments or requires I/O belongs in :mod:`backend.config.settings`.
"""

from __future__ import annotations

APP_NAME: str = "ScholarBird Backend"
APP_VERSION: str = "1.0"
DEFAULT_LOG_LEVEL: str = "INFO"

LOG_FORMAT: str = (
    "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
)

# Firestore collection names — kept in sync with the existing Flutter app.
FIRESTORE_COLLECTION_SCHOLARSHIPS: str = "scholarships"
FIRESTORE_COLLECTION_USERS: str = "users"
FIRESTORE_SUBCOLLECTION_APPLICATIONS: str = "applications"
FIRESTORE_SUBCOLLECTION_SAVED: str = "savedScholarships"

# Scholarship document field names — mirror lib/admin/add_scholarship_page.dart.
FIELD_TITLE: str = "title"
FIELD_COUNTRY: str = "country"
FIELD_DEGREE: str = "degree"
FIELD_FIELD: str = "field"
FIELD_DEADLINE: str = "deadline"
FIELD_AMOUNT: str = "amount"
FIELD_FUNDING_TYPE: str = "fundingType"
FIELD_IMAGE: str = "image"
FIELD_DESCRIPTION: str = "description"
FIELD_LINK: str = "link"
FIELD_MIN_CGPA: str = "minCgpa"
FIELD_IELTS_REQUIRED: str = "ieltsRequired"
FIELD_RESEARCH_REQUIRED: str = "researchRequired"
FIELD_IS_FEATURED: str = "isFeatured"
FIELD_IS_HIDDEN: str = "isHidden"
FIELD_CREATED_AT: str = "createdAt"
FIELD_UPDATED_AT: str = "updatedAt"

# ---------------------------------------------------------------------------
# Orchestrator / registry defaults
# ---------------------------------------------------------------------------

#: Default number of worker threads when parallel execution is enabled.
DEFAULT_MAX_WORKERS: int = 3

#: Default parallelism switch (sequential when ``False``).
DEFAULT_ENABLE_PARALLEL: bool = False

#: Action labels emitted by the orchestrator when summarising Firestore
#: uploads. Kept as constants so the console output stays consistent
#: with :class:`UploadOutcome.action`.
UPLOAD_ACTION_INSERTED: str = "inserted"
UPLOAD_ACTION_UPDATED: str = "updated"
UPLOAD_ACTION_SKIPPED: str = "skipped"
UPLOAD_ACTION_FAILED: str = "failed"
