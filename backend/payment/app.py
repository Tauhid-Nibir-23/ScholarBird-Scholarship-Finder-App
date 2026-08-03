"""Standalone FastAPI app exposing the payment foundation."""

from __future__ import annotations

import sys
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

load_dotenv(_PROJECT_ROOT.parent / ".env")

from backend.core.logger import configure_logging  # noqa: E402
from backend.config.settings import get_settings  # noqa: E402
from .routes import router, sandbox_router  # noqa: E402

settings = get_settings()
configure_logging(level=settings.log_level)

app = FastAPI(title="ScholarBird Payment API", version="1.0.0")
app.include_router(router)
app.include_router(sandbox_router)
