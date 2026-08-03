"""Production-grade Premium Subscription management for ScholarBird backend.

Implements Firestore subscription activation, renewal/extension,
auto-expiration checks, payment history tracking, admin overrides,
and single-read subscription validation.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, Optional, Union

from backend.firebase import get_firestore_client

logger = logging.getLogger(__name__)

# Configurable plan durations (in days)
PLAN_DURATIONS_DAYS: Dict[str, int] = {
    "monthly": 30,
    "6months": 180,
    "yearly": 365,
}


def _parse_datetime(value: Any) -> Optional[datetime]:
    """Safely parse a Firestore Timestamp, datetime, or ISO string into UTC datetime."""
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    if hasattr(value, "to_datetime"):
        dt = value.to_datetime()
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            return None
    return None


class SubscriptionManager:
    """Handles Firestore subscription activation, extension, expiration, and payment logging."""

    def __init__(self, db_client: Any = None) -> None:
        self._db = db_client

    @property
    def db(self) -> Any:
        if self._db is None:
            self._db = get_firestore_client()
        return self._db

    def activate_or_extend_subscription(
        self,
        uid: str,
        plan: str,
        gateway: str = "sslcommerz",
        payment_id: str = "",
        transaction_id: str = "",
        amount: float = 0.0,
        currency: str = "BDT",
        status: str = "VALIDATED",
    ) -> Dict[str, Any]:
        """Activate or extend a user subscription in Firestore.
        
        Exact Firestore fields matching Flutter SubscriptionModel:
          - subscriptionStatus
          - subscriptionPlan
          - subscriptionStart
          - subscriptionExpiry
          - paymentGateway
          - lastPaymentId
          - lastTransactionId

        Expiry Extension Logic:
          expiry = max(currentExpiry, now) + duration
        """
        now = datetime.now(timezone.utc)
        clean_plan = (plan or "monthly").strip().lower()
        duration_days = PLAN_DURATIONS_DAYS.get(clean_plan, 30)
        duration = timedelta(days=duration_days)

        user_ref = self.db.collection("users").doc(uid)
        doc = user_ref.get()  # Exactly 1 read

        existing_expiry: Optional[datetime] = None
        if doc.exists:
            data = doc.to_dict() or {}
            existing_expiry = _parse_datetime(data.get("subscriptionExpiry"))

        # If current subscription is active and has not expired, extend from existing expiry.
        # Otherwise start from now.
        start_base = now
        if existing_expiry and existing_expiry > now:
            start_base = existing_expiry

        new_expiry = start_base + duration

        subscription_data = {
            "subscriptionStatus": "premium",
            "subscriptionPlan": clean_plan,
            "subscriptionStart": now,
            "subscriptionExpiry": new_expiry,
            "paymentGateway": gateway,
            "lastPaymentId": str(payment_id or transaction_id),
            "lastTransactionId": str(transaction_id or payment_id),
        }

        # Update user doc (set with merge=True to preserve existing profile fields)
        user_ref.set(subscription_data, merge=True)

        # Record payment history entry under users/{uid}/payments/{transaction_id}
        pay_doc_id = str(transaction_id or payment_id or uuid.uuid4().hex)
        payment_record = {
            "paymentId": str(payment_id or transaction_id),
            "transactionId": str(transaction_id or payment_id),
            "gateway": gateway,
            "amount": float(amount),
            "currency": currency,
            "plan": clean_plan,
            "status": status,
            "createdAt": now,
        }
        user_ref.collection("payments").doc(pay_doc_id).set(payment_record, merge=True)

        logger.info(
            "Activated/extended subscription for user %s: plan=%s, expiry=%s",
            uid,
            clean_plan,
            new_expiry.isoformat(),
        )

        return {
            "uid": uid,
            "subscriptionStatus": "premium",
            "subscriptionPlan": clean_plan,
            "subscriptionStart": now,
            "subscriptionExpiry": new_expiry,
            "paymentGateway": gateway,
            "lastPaymentId": str(payment_id or transaction_id),
            "lastTransactionId": str(transaction_id or payment_id),
        }

    def get_subscription_state(self, uid: str) -> Dict[str, Any]:
        """Fetch and return subscription state using at most ONE Firestore read.
        
        Automatically converts expired subscriptions to 'free' state.
        """
        now = datetime.now(timezone.utc)
        user_ref = self.db.collection("users").doc(uid)
        doc = user_ref.get()  # Exactly 1 read

        if not doc.exists:
            return {
                "uid": uid,
                "status": "free",
                "is_premium": False,
                "plan": None,
                "start": None,
                "expiry": None,
                "days_remaining": 0,
                "gateway": None,
                "last_transaction_id": None,
            }

        data = doc.to_dict() or {}
        raw_status = str(data.get("subscriptionStatus") or "free").lower()
        expiry = _parse_datetime(data.get("subscriptionExpiry"))
        start = _parse_datetime(data.get("subscriptionStart"))
        plan = data.get("subscriptionPlan")
        gateway = data.get("paymentGateway")
        last_tx = data.get("lastTransactionId")

        is_premium = False
        days_remaining = 0

        if raw_status == "premium" and expiry:
            if expiry > now:
                is_premium = True
                days_remaining = max(0, (expiry - now).days)
            else:
                # Expired: auto-update to free (without deleting payment history)
                raw_status = "free"
                is_premium = False
                days_remaining = 0
                try:
                    user_ref.update({"subscriptionStatus": "free"})
                except Exception as exc:
                    logger.warning("Failed to auto-expire user doc %s: %s", uid, exc)

        return {
            "uid": uid,
            "status": "premium" if is_premium else "free",
            "is_premium": is_premium,
            "plan": plan if is_premium else None,
            "start": start.isoformat() if start else None,
            "expiry": expiry.isoformat() if expiry else None,
            "days_remaining": days_remaining,
            "gateway": gateway,
            "last_transaction_id": last_tx,
        }

    def grant_admin_override(
        self, uid: str, plan: str = "monthly", custom_days: Optional[int] = None
    ) -> Dict[str, Any]:
        """Allow admin to grant premium status without payment."""
        days = custom_days or PLAN_DURATIONS_DAYS.get(plan.lower(), 30)
        now = datetime.now(timezone.utc)
        new_expiry = now + timedelta(days=days)
        tx_id = f"ADMIN_GRANT_{uuid.uuid4().hex[:8]}"

        user_ref = self.db.collection("users").doc(uid)
        subscription_data = {
            "subscriptionStatus": "premium",
            "subscriptionPlan": plan.lower(),
            "subscriptionStart": now,
            "subscriptionExpiry": new_expiry,
            "paymentGateway": "admin_override",
            "lastPaymentId": "ADMIN_GRANT",
            "lastTransactionId": tx_id,
        }
        user_ref.set(subscription_data, merge=True)

        payment_record = {
            "paymentId": "ADMIN_GRANT",
            "transactionId": tx_id,
            "gateway": "admin_override",
            "amount": 0.0,
            "currency": "BDT",
            "plan": plan.lower(),
            "status": "GRANTED",
            "createdAt": now,
        }
        user_ref.collection("payments").doc(tx_id).set(payment_record, merge=True)

        logger.info("Admin granted premium to user %s until %s", uid, new_expiry.isoformat())
        return {
            "subscriptionStatus": "premium",
            "subscriptionPlan": plan.lower(),
            "subscriptionStart": now.isoformat(),
            "subscriptionExpiry": new_expiry.isoformat(),
            "paymentGateway": "admin_override",
            "lastPaymentId": "ADMIN_GRANT",
            "lastTransactionId": tx_id,
        }

    def revoke_admin_override(self, uid: str) -> Dict[str, Any]:
        """Allow admin to revoke premium status without deleting payment history."""
        now = datetime.now(timezone.utc)
        user_ref = self.db.collection("users").doc(uid)
        update_data = {
            "subscriptionStatus": "free",
            "subscriptionExpiry": now,
        }
        user_ref.set(update_data, merge=True)
        logger.info("Admin revoked premium from user %s", uid)
        return {"uid": uid, "status": "free"}


def is_premium(user_data_or_uid: Union[str, Dict[str, Any]], db_client: Any = None) -> bool:
    """Reusable helper/middleware to evaluate if a user has active premium status.
    
    If passed a dict (Firestore doc data), performs 0 network reads.
    If passed a string (UID), performs at most 1 Firestore read.
    """
    now = datetime.now(timezone.utc)
    if isinstance(user_data_or_uid, dict):
        status = str(user_data_or_uid.get("subscriptionStatus") or "free").lower()
        expiry = _parse_datetime(user_data_or_uid.get("subscriptionExpiry"))
        return status == "premium" and expiry is not None and expiry > now

    if isinstance(user_data_or_uid, str) and user_data_or_uid.strip():
        manager = SubscriptionManager(db_client=db_client)
        state = manager.get_subscription_state(user_data_or_uid.strip())
        return bool(state.get("is_premium"))

    return False
