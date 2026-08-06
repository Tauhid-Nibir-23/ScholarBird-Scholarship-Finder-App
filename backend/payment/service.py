"""Gateway-aware PaymentService facade.

Selects between the real SSLCommerz integration and the development-only
Mock gateway based on the ``PAYMENT_GATEWAY`` environment variable.
Defaults to ``mock`` so local development works out of the box.
"""

from __future__ import annotations

import logging
import os
from typing import Any

from .mock_gateway import (
    DuplicateTransactionError,
    MockGatewayService,
    PaymentError,
)
from .models import (
    PaymentCallbackPayload,
    PaymentCreateRequest,
    PaymentCreateResponse,
    PaymentValidationRequest,
    PaymentValidationResponse,
    SandboxPaymentCreateRequest,
)

logger = logging.getLogger(__name__)


def resolve_gateway_name() -> str:
    """Return the active gateway name (``mock`` or ``sslcommerz``)."""
    raw = os.getenv("PAYMENT_GATEWAY", "mock").strip().lower()
    return raw if raw in {"mock", "sslcommerz"} else "mock"


class PaymentService:
    """Facade that exposes a single API regardless of the underlying gateway."""

    def __init__(self) -> None:
        gateway = resolve_gateway_name()
        if gateway == "sslcommerz":
            # Imported lazily so the mock flow has zero SSLCommerz dependency.
            from .sslcommerz_service import SSLCommerzPaymentService

            self._impl: Any = SSLCommerzPaymentService()
            self._name = "sslcommerz"
        else:
            self._impl = MockGatewayService()
            self._name = "mock"
        logger.info("Payment gateway initialised: %s", self._name)

    @property
    def gateway_name(self) -> str:
        return self._name

    def create_payment(self, request: PaymentCreateRequest) -> PaymentCreateResponse:
        return self._impl.create_payment(request)

    def create_sandbox_payment(self, request: SandboxPaymentCreateRequest) -> PaymentCreateResponse:
        return self._impl.create_sandbox_payment(request)

    def validate_payment(self, request: PaymentValidationRequest) -> PaymentValidationResponse:
        return self._impl.validate_payment(request)

    def handle_callback(self, route_name: str, payload: PaymentCallbackPayload) -> dict[str, Any]:
        return self._impl.handle_callback(route_name, payload)


__all__ = [
    "PaymentError",
    "DuplicateTransactionError",
    "PaymentService",
    "resolve_gateway_name",
]
