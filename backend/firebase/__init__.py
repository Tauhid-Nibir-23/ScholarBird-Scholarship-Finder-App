"""Firebase integration package.

The package exposes:

* :func:`get_firebase_app` — lazy singleton accessor for the
  Firebase Admin SDK application.
* :func:`get_firestore_client` — lazy singleton accessor for the
  Firestore client.
* :class:`FirestoreUploader` — the batch upsert engine that
  persists :class:`backend.models.scholarship.Scholarship` records
  to the ``scholarships`` collection.
* :class:`UploadOutcome` and :class:`UploadSummary` — result
  containers returned by the uploader.
"""

from backend.firebase.firebase_config import (
    get_firebase_app,
    get_firestore_client,
    reset_firebase_state,
)
from backend.firebase.upload import (
    FirestoreUploader,
    UploadOutcome,
    UploadSummary,
)

__all__ = [
    "get_firebase_app",
    "get_firestore_client",
    "reset_firebase_state",
    "FirestoreUploader",
    "UploadOutcome",
    "UploadSummary",
]