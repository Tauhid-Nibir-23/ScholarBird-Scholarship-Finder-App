"""Utility helpers for SSLCommerz payments."""

from __future__ import annotations

import hashlib
import logging
import secrets
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Mapping

logger = logging.getLogger(__name__)


def generate_transaction_id(uid: str, subscription_plan: str) -> str:
    """Generate a collision-resistant transaction id."""
    token = secrets.token_hex(8)
    digest = hashlib.sha256(f"{uid}:{subscription_plan}:{token}".encode("utf-8")).hexdigest()[:12]
    return f"SB-{subscription_plan[:4].upper()}-{digest}"


def normalize_amount(amount: float | Decimal) -> str:
    """Format an amount as a two-decimal SSLCommerz string."""
    decimal_amount = Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{decimal_amount:.2f}"


def is_sandbox_enabled(raw_value: str | None) -> bool:
    """Interpret the sandbox flag from environment variables."""
    if raw_value is None:
        return True
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def safe_log_payload(payload: Mapping[str, Any]) -> dict[str, Any]:
    """Remove sensitive fields before logging payment payloads."""
    redacted = dict(payload)
    redacted.pop("store_passwd", None)
    redacted.pop("store_password", None)
    return redacted
