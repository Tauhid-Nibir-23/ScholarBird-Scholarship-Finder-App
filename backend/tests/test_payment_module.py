"""Tests for the SSLCommerz payment foundation."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(_PROJECT_ROOT))

from backend.payment.app import app  # noqa: E402
from backend.payment.models import PaymentCreateRequest, PaymentValidationRequest  # noqa: E402
from backend.payment.service import PaymentService, SSLCommerzConfig  # noqa: E402


class _DummyResponse:
    def __init__(self, payload: dict[str, Any]) -> None:
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict[str, Any]:
        return self._payload


class _DummyClient:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload
        self.post_calls: list[tuple[str, dict[str, Any] | None]] = []
        self.get_calls: list[tuple[str, dict[str, Any] | None]] = []

    def __enter__(self) -> "_DummyClient":
        return self

    def __exit__(self, *exc: Any) -> None:
        return None

    def post(self, url: str, data: dict[str, Any]) -> _DummyResponse:
        self.post_calls.append((url, data))
        return _DummyResponse(self.payload)

    def get(self, url: str, params: dict[str, Any]) -> _DummyResponse:
        self.get_calls.append((url, params))
        return _DummyResponse(self.payload)


@pytest.fixture(autouse=True)
def _payment_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SSLCOMMERZ_STORE_ID", "testbox")
    monkeypatch.setenv("SSLCOMMERZ_STORE_PASSWORD", "qwerty")
    monkeypatch.setenv("SSLCOMMERZ_SANDBOX", "true")
    monkeypatch.setenv("SSLCOMMERZ_API", "https://sandbox.sslcommerz.com/gwprocess/v4/api.php")
    monkeypatch.setenv("SSLCOMMERZ_VALIDATION_API", "https://sandbox.sslcommerz.com/validator/api/validationserverAPI.php")


def _create_request() -> PaymentCreateRequest:
    return PaymentCreateRequest(
        uid="uid-123",
        subscription_plan="monthly",
        total_amount=299.0,
        customer={
            "name": "Test User",
            "email": "test@example.com",
            "address1": "Dhaka",
            "address2": "Dhaka",
            "city": "Dhaka",
            "state": "Dhaka",
            "postcode": "1000",
            "country": "Bangladesh",
            "phone": "01711111111",
            "fax": "",
        },
    )


def test_create_payment_uses_gateway_url(monkeypatch: pytest.MonkeyPatch) -> None:
    service = PaymentService(SSLCommerzConfig.from_env())
    dummy = _DummyClient({"status": "SUCCESS", "GatewayPageURL": "https://gateway.example.com/pay"})
    monkeypatch.setattr("backend.payment.service.httpx.Client", lambda timeout: dummy)

    response = service.create_payment(_create_request())

    assert response.transaction_id.startswith("SB-")
    assert response.gateway_url == "https://gateway.example.com/pay"
    assert dummy.post_calls


def test_validate_payment_returns_status(monkeypatch: pytest.MonkeyPatch) -> None:
    service = PaymentService(SSLCommerzConfig.from_env())
    dummy = _DummyClient({"status": "VALIDATED", "tran_id": "tran-1", "val_id": "val-1", "amount": "299.00", "currency": "BDT"})
    monkeypatch.setattr("backend.payment.service.httpx.Client", lambda timeout: dummy)

    response = service.validate_payment(PaymentValidationRequest(transaction_id="tran-1"))

    assert response.status == "VALIDATED"
    assert response.transaction_id == "tran-1"
    assert response.validation_id == "val-1"


def test_fastapi_routes_expose_payment_endpoints() -> None:
    client = TestClient(app)
    paths = set(client.get("/openapi.json").json()["paths"].keys())
    assert "/api/payment/create" in paths
    assert "/api/payment/validate" in paths
    assert "/api/payment/success" in paths
    assert "/api/payment/fail" in paths
    assert "/api/payment/cancel" in paths
    assert "/api/payment/ipn" in paths
