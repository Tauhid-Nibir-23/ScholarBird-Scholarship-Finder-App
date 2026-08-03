"""Tests for production-grade Premium Subscription management."""

from __future__ import annotations

import os
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Dict

import pytest
from fastapi.testclient import TestClient

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_PROJECT_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(_PROJECT_ROOT))

from backend.payment.app import app  # noqa: E402
from backend.payment.subscription import SubscriptionManager, is_premium  # noqa: E402


class MockDocSnapshot:
    def __init__(self, doc_id: str, data: Dict[str, Any] | None) -> None:
        self.id = doc_id
        self._data = data
        self.exists = data is not None

    def to_dict(self) -> Dict[str, Any] | None:
        return self._data

    def get(self, field: str) -> Any:
        if self._data:
            return self._data.get(field)
        return None


class MockCollectionRef:
    def __init__(self, store: Dict[str, Any], path: str) -> None:
        self.store = store
        self.path = path

    def doc(self, doc_id: str) -> MockDocumentRef:
        doc_path = f"{self.path}/{doc_id}"
        return MockDocumentRef(self.store, doc_path)


class MockDocumentRef:
    def __init__(self, store: Dict[str, Any], path: str) -> None:
        self.store = store
        self.path = path
        self.read_count = 0

    def get(self) -> MockDocSnapshot:
        self.store["_read_count"] = self.store.get("_read_count", 0) + 1
        data = self.store.get(self.path)
        return MockDocSnapshot(self.path.split("/")[-1], data)

    def set(self, data: Dict[str, Any], merge: bool = False) -> None:
        if merge and self.path in self.store and isinstance(self.store[self.path], dict):
            self.store[self.path].update(data)
        else:
            self.store[self.path] = dict(data)

    def update(self, data: Dict[str, Any]) -> None:
        if self.path in self.store and isinstance(self.store[self.path], dict):
            self.store[self.path].update(data)
        else:
            self.store[self.path] = dict(data)

    def collection(self, col_name: str) -> MockCollectionRef:
        return MockCollectionRef(self.store, f"{self.path}/{col_name}")


class MockFirestoreClient:
    def __init__(self) -> None:
        self.store: Dict[str, Any] = {}

    def collection(self, name: str) -> MockCollectionRef:
        return MockCollectionRef(self.store, name)


@pytest.fixture
def mock_db() -> MockFirestoreClient:
    return MockFirestoreClient()


def test_subscription_activation(mock_db: MockFirestoreClient) -> None:
    manager = SubscriptionManager(db_client=mock_db)
    result = manager.activate_or_extend_subscription(
        uid="user-1",
        plan="monthly",
        gateway="sslcommerz",
        payment_id="val-100",
        transaction_id="SB-MONT-100",
        amount=299.0,
        currency="BDT",
    )

    assert result["subscriptionStatus"] == "premium"
    assert result["subscriptionPlan"] == "monthly"
    assert result["paymentGateway"] == "sslcommerz"
    assert result["lastPaymentId"] == "val-100"
    assert result["lastTransactionId"] == "SB-MONT-100"

    # Verify exact user doc fields in Firestore
    user_data = mock_db.store["users/user-1"]
    assert user_data["subscriptionStatus"] == "premium"
    assert user_data["subscriptionPlan"] == "monthly"
    assert user_data["subscriptionStart"] is not None
    assert user_data["subscriptionExpiry"] is not None

    # Verify payment history record created under users/{uid}/payments/{tx_id}
    pay_data = mock_db.store["users/user-1/payments/SB-MONT-100"]
    assert pay_data["amount"] == 299.0
    assert pay_data["gateway"] == "sslcommerz"
    assert pay_data["status"] == "VALIDATED"


def test_expiry_extension(mock_db: MockFirestoreClient) -> None:
    manager = SubscriptionManager(db_client=mock_db)
    now = datetime.now(timezone.utc)
    future_expiry = now + timedelta(days=15)

    # User already has 15 days remaining
    mock_db.store["users/user-2"] = {
        "subscriptionStatus": "premium",
        "subscriptionPlan": "monthly",
        "subscriptionExpiry": future_expiry,
    }

    # User buys another monthly plan (+30 days)
    manager.activate_or_extend_subscription(
        uid="user-2",
        plan="monthly",
        gateway="sslcommerz",
        transaction_id="SB-MONT-200",
    )

    user_data = mock_db.store["users/user-2"]
    new_expiry = user_data["subscriptionExpiry"]
    # Expected expiry: future_expiry + 30 days = now + 45 days
    expected_days = (new_expiry - now).days
    assert expected_days >= 44 and expected_days <= 46


def test_auto_expiration(mock_db: MockFirestoreClient) -> None:
    manager = SubscriptionManager(db_client=mock_db)
    past_expiry = datetime.now(timezone.utc) - timedelta(days=5)

    mock_db.store["users/user-3"] = {
        "subscriptionStatus": "premium",
        "subscriptionPlan": "monthly",
        "subscriptionExpiry": past_expiry,
    }
    mock_db.store["users/user-3/payments/SB-OLD"] = {
        "amount": 299.0,
        "status": "VALIDATED",
    }

    # Fetching subscription state auto-expires past subscription
    state = manager.get_subscription_state("user-3")
    assert state["status"] == "free"
    assert state["is_premium"] is False

    # User document updated to free
    assert mock_db.store["users/user-3"]["subscriptionStatus"] == "free"
    # Payment history preserved
    assert "users/user-3/payments/SB-OLD" in mock_db.store


def test_subscription_validation_single_read(mock_db: MockFirestoreClient) -> None:
    manager = SubscriptionManager(db_client=mock_db)
    mock_db.store["users/user-4"] = {
        "subscriptionStatus": "premium",
        "subscriptionPlan": "yearly",
        "subscriptionExpiry": datetime.now(timezone.utc) + timedelta(days=365),
    }

    mock_db.store["_read_count"] = 0
    state = manager.get_subscription_state("user-4")

    assert state["is_premium"] is True
    assert state["plan"] == "yearly"
    # Verify at most 1 Firestore read was performed
    assert mock_db.store["_read_count"] == 1


def test_is_premium_helper(mock_db: MockFirestoreClient) -> None:
    future_expiry = datetime.now(timezone.utc) + timedelta(days=10)
    past_expiry = datetime.now(timezone.utc) - timedelta(days=10)

    # Pass dictionary directly (0 network reads)
    assert is_premium({"subscriptionStatus": "premium", "subscriptionExpiry": future_expiry}) is True
    assert is_premium({"subscriptionStatus": "premium", "subscriptionExpiry": past_expiry}) is False
    assert is_premium({"subscriptionStatus": "free"}) is False

    # Pass string UID (uses 1 read)
    mock_db.store["users/user-5"] = {
        "subscriptionStatus": "premium",
        "subscriptionExpiry": future_expiry,
    }
    assert is_premium("user-5", db_client=mock_db) is True


def test_admin_grant_and_revoke(mock_db: MockFirestoreClient) -> None:
    manager = SubscriptionManager(db_client=mock_db)

    # Grant admin override
    grant_res = manager.grant_admin_override(uid="user-admin-1", plan="yearly", custom_days=365)
    assert grant_res["subscriptionStatus"] == "premium"
    assert grant_res["paymentGateway"] == "admin_override"

    state = manager.get_subscription_state("user-admin-1")
    assert state["is_premium"] is True

    # Revoke admin override
    manager.revoke_admin_override(uid="user-admin-1")
    state_after = manager.get_subscription_state("user-admin-1")
    assert state_after["is_premium"] is False
    # Payment history preserved
    assert len([k for k in mock_db.store.keys() if k.startswith("users/user-admin-1/payments/")]) > 0


def test_api_routes_subscription(monkeypatch: pytest.MonkeyPatch, mock_db: MockFirestoreClient) -> None:
    client = TestClient(app)

    # Mock SubscriptionManager inside subscription module to use mock_db
    monkeypatch.setattr("backend.payment.subscription.SubscriptionManager", lambda db_client=None: SubscriptionManager(db_client=mock_db))

    # Test GET subscription state endpoint
    response = client.get("/api/payment/subscription/nonexistent-user")
    assert response.status_code == 200
    assert response.json()["status"] == "free"

    # Test Admin Grant API endpoint
    grant_resp = client.post("/api/payment/admin/grant", json={"uid": "test-admin-uid", "plan": "6months"})
    assert grant_resp.status_code == 200
    assert grant_resp.json()["subscriptionStatus"] == "premium"

    # Verify state via GET API
    sub_resp = client.get("/api/payment/subscription/test-admin-uid")
    assert sub_resp.status_code == 200
    assert sub_resp.json()["is_premium"] is True

    # Test Admin Revoke API endpoint
    revoke_resp = client.post("/api/payment/admin/revoke", json={"uid": "test-admin-uid"})
    assert revoke_resp.status_code == 200

    sub_resp_after = client.get("/api/payment/subscription/test-admin-uid")
    assert sub_resp_after.json()["is_premium"] is False
