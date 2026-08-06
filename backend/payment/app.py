"""Standalone FastAPI app exposing the payment foundation."""

from __future__ import annotations

import sys
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

load_dotenv(_PROJECT_ROOT.parent / ".env")

from backend.core.logger import configure_logging  # noqa: E402
from backend.config.settings import get_settings  # noqa: E402
from .routes import checkout_router, router, sandbox_router  # noqa: E402

settings = get_settings()
configure_logging(level=settings.log_level)

app = FastAPI(title="ScholarBird Payment API", version="1.0.0")

# Allow the Flutter web preview (served on a different localhost port) to
# call the payment API during development. Restricted to the dev origins we
# actually use; switch to a strict allow-list when shipping to production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:51538",
        "http://127.0.0.1:51538",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
app.include_router(sandbox_router)
app.include_router(checkout_router)
