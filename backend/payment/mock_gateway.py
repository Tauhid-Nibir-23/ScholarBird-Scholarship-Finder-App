"""Development-only Mock Payment Gateway.

Mirrors the SSLCommerz `PaymentService` interface so the rest of the
backend (routes, subscription activation, Firestore writes) stays
identical. No external HTTP is performed; the checkout page is served
locally and triggers the same success/cancel callback paths.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Mapping
from urllib.parse import urlencode

from backend.core.exceptions import ScholarBirdError

from .models import (
    PaymentCallbackPayload,
    PaymentCreateRequest,
    PaymentCreateResponse,
    PaymentValidationRequest,
    PaymentValidationResponse,
    PaymentStatus,
    SandboxPaymentCreateRequest,
)
from .utils import generate_transaction_id, normalize_amount, safe_log_payload

logger = logging.getLogger(__name__)


class PaymentError(ScholarBirdError):
    """Raised when a mock payment operation fails."""


class DuplicateTransactionError(PaymentError):
    """Raised when the same transaction id is created twice."""


class MockGatewayService:
    """In-memory payment service that emulates SSLCommerz for development."""

    def __init__(self) -> None:
        self._transactions: dict[str, dict[str, Any]] = {}

    @staticmethod
    def _resolve_callback_base(request: PaymentCreateRequest | SandboxPaymentCreateRequest) -> str:
        # The Flutter WebView intercepts /success, /fail, /cancel paths.
        # Use a localhost callback so the embedded WebView can resolve the URL.
        return os.getenv("MOCK_CALLBACK_BASE", "http://localhost:8000").rstrip("/")

    def _build_checkout_url(
        self,
        transaction_id: str,
        plan: str,
        amount: float,
        currency: str,
        uid: str,
    ) -> str:
        params = urlencode(
            {
                "transaction_id": transaction_id,
                "plan": plan,
                "amount": normalize_amount(amount),
                "currency": currency,
                "uid": uid,
            }
        )
        return f"/payment/mock-checkout?{params}"

    def create_payment(self, request: PaymentCreateRequest) -> PaymentCreateResponse:
        """Create a mock checkout session and return the local URL."""
        transaction_id = generate_transaction_id(request.uid, request.subscription_plan)
        if transaction_id in self._transactions:
            raise DuplicateTransactionError(f"Duplicate transaction id generated: {transaction_id}")

        self._transactions[transaction_id] = {
            "request": request.model_dump(),
            "status": PaymentStatus.PENDING.value,
            "uid": request.uid,
            "plan": request.subscription_plan,
            "amount": float(request.total_amount),
            "currency": request.currency,
        }

        gateway_url = self._build_checkout_url(
            transaction_id=transaction_id,
            plan=request.subscription_plan,
            amount=float(request.total_amount),
            currency=request.currency,
            uid=request.uid,
        )
        logger.info("Mock session created: %s -> %s", transaction_id, gateway_url)
        return PaymentCreateResponse(gateway_url=gateway_url, transaction_id=transaction_id)

    def create_sandbox_payment(self, request: SandboxPaymentCreateRequest) -> PaymentCreateResponse:
        """Create a mock sandbox session."""
        transaction_id = generate_transaction_id(request.uid, request.plan)
        if transaction_id in self._transactions:
            raise DuplicateTransactionError(f"Duplicate transaction id generated: {transaction_id}")

        self._transactions[transaction_id] = {
            "uid": request.uid,
            "plan": request.plan,
            "amount": float(request.amount),
            "currency": "BDT",
            "status": PaymentStatus.PENDING.value,
        }
        gateway_url = self._build_checkout_url(
            transaction_id=transaction_id,
            plan=request.plan,
            amount=float(request.amount),
            currency="BDT",
            uid=request.uid,
        )
        return PaymentCreateResponse(gateway_url=gateway_url, transaction_id=transaction_id)

    def validate_payment(self, request: PaymentValidationRequest) -> PaymentValidationResponse:
        """Return a synthetic VALID response mirroring SSLCommerz shape."""
        transaction_id = (
            request.transaction_id
            or request.val_id
            or request.session_key
            or ""
        ).strip()
        if not transaction_id:
            raise PaymentError("A transaction id, val_id, or session key is required")

        record = self._transactions.get(transaction_id, {})
        if not record:
            raise PaymentError(f"Unknown mock transaction id: {transaction_id}")

        status = str(record.get("status", "PENDING")).upper()
        amount = str(record.get("amount", "0.00"))
        currency = str(record.get("currency", "BDT"))

        return PaymentValidationResponse(
            status=status,
            transaction_id=transaction_id,
            validation_id=f"MOCKVAL-{transaction_id}",
            amount=amount,
            currency=currency,
            raw={
                "status": status,
                "tran_id": transaction_id,
                "val_id": f"MOCKVAL-{transaction_id}",
                "amount": amount,
                "currency": currency,
                "gateway": "mock",
            },
        )

    def handle_callback(self, route_name: str, payload: PaymentCallbackPayload) -> dict[str, Any]:
        """Record callbacks and activate subscriptions on success."""
        transaction_id = (
            payload.transaction_id or payload.sessionkey or payload.val_id or ""
        ).strip()
        logger.info("Mock %s callback received: %s", route_name, safe_log_payload(payload.model_dump(mode="json")))

        if transaction_id:
            record = self._transactions.setdefault(transaction_id, {})
            record[f"callback_{route_name}"] = payload.model_dump(mode="json")
            if route_name == "success":
                record["status"] = "VALIDATED"
            elif route_name == "cancel":
                record["status"] = PaymentStatus.CANCELLED.value
            elif route_name == "fail":
                record["status"] = PaymentStatus.FAILED.value

        if route_name == "success":
            transaction = self._transactions.get(transaction_id, {})
            uid = (payload.uid or transaction.get("uid") or "").strip()
            plan = (payload.plan or transaction.get("plan") or "monthly").strip()
            if not uid:
                raise PaymentError("Mock success callback is missing the user id")

            from .subscription import SubscriptionManager

            SubscriptionManager().activate_or_extend_subscription(
                uid=uid,
                plan=plan,
                gateway="mock",
                payment_id=payload.val_id or transaction_id,
                transaction_id=transaction_id,
                amount=float(payload.amount or transaction.get("amount") or 0),
                currency=payload.currency or transaction.get("currency") or "BDT",
                status="VALIDATED",
            )

        return {
            "status": "accepted",
            "route": route_name,
            "transaction_id": transaction_id,
        }

    def render_checkout_page(self, params: Mapping[str, str]) -> str:
        """Render a simple HTML checkout page with Pay Now / Cancel buttons."""
        transaction_id = params.get("transaction_id", "")
        plan = params.get("plan", "monthly")
        amount = params.get("amount", "0.00")
        currency = params.get("currency", "BDT")
        uid = params.get("uid", "")

        # POST body for the success/cancel callbacks. Mirrors SSLCommerz
        # callback fields so PaymentCallbackPayload accepts it directly.
        success_body = (
            f"tran_id={transaction_id}"
            f"&val_id=MOCKVAL-{transaction_id}"
            f"&status=VALID"
            f"&amount={amount}"
            f"&currency={currency}"
            f"&value_a={uid}"
            f"&value_b={plan}"
        )
        cancel_body = (
            f"tran_id={transaction_id}"
            f"&status=CANCELLED"
            f"&amount={amount}"
            f"&currency={currency}"
            f"&value_a={uid}"
            f"&value_b={plan}"
        )

        return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>ScholarBird Mock Checkout</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #5B7AE8 0%, #1A1A2E 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
      color: #1A1A2E;
    }}
    .card {{
      background: #ffffff;
      width: 100%;
      max-width: 420px;
      border-radius: 18px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.25);
      overflow: hidden;
    }}
    .header {{
      background: #1A1A2E;
      color: #fff;
      padding: 22px 24px;
      display: flex;
      align-items: center;
      gap: 12px;
    }}
    .logo {{
      width: 40px; height: 40px;
      border-radius: 10px;
      background: #5B7AE8;
      display: flex; align-items: center; justify-content: center;
      font-weight: 800; font-size: 18px;
    }}
    .header h1 {{ margin: 0; font-size: 18px; font-weight: 700; }}
    .header small {{ display: block; color: #9aa3b8; font-size: 11px; margin-top: 2px; }}
    .badge {{
      margin-left: auto;
      background: #f59e0b;
      color: #1A1A2E;
      font-size: 11px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 999px;
    }}
    .body {{ padding: 24px; }}
    .row {{ display: flex; justify-content: space-between; padding: 10px 0; font-size: 14px; }}
    .row + .row {{ border-top: 1px solid #eef2f7; }}
    .row span:first-child {{ color: #6B7A95; }}
    .row span:last-child {{ font-weight: 700; }}
    .total {{
      margin-top: 14px;
      padding: 14px 16px;
      background: #EEF2FF;
      border-radius: 12px;
      display: flex;
      justify-content: space-between;
      font-size: 16px;
      font-weight: 800;
      color: #1A1A2E;
    }}
    .actions {{ display: flex; gap: 10px; margin-top: 22px; }}
    .btn {{
      flex: 1;
      padding: 14px 0;
      font-size: 15px;
      font-weight: 700;
      border: none;
      border-radius: 12px;
      cursor: pointer;
    }}
    .btn-primary {{
      background: #5B7AE8; color: #fff;
    }}
    .btn-primary:hover {{ background: #4a66d4; }}
    .btn-secondary {{
      background: #fff; color: #1A1A2E; border: 1px solid #e2e8f0;
    }}
    .meta {{ margin-top: 16px; font-size: 11px; color: #6B7A95; text-align: center; }}
    code {{ background: #EEF2FF; padding: 2px 6px; border-radius: 4px; }}
  </style>
</head>
<body>
  <div class=\"card\">
    <div class=\"header\">
      <div class=\"logo\">SB</div>
      <div>
        <h1>ScholarBird Mock Gateway</h1>
        <small>Development-only payment simulation</small>
      </div>
      <span class=\"badge\">DEMO</span>
    </div>
    <div class=\"body\">
      <div class=\"row\"><span>Plan</span><span>{plan.upper()}</span></div>
      <div class=\"row\"><span>User ID</span><span><code>{uid}</code></span></div>
      <div class=\"row\"><span>Transaction</span><span><code>{transaction_id}</code></span></div>
      <div class=\"total\"><span>Total</span><span>{currency} {amount}</span></div>

      <form class=\"actions\" method=\"POST\" action=\"/api/payment/success\">
        <input type=\"hidden\" name=\"tran_id\" value=\"{transaction_id}\" />
        <input type=\"hidden\" name=\"val_id\" value=\"MOCKVAL-{transaction_id}\" />
        <input type=\"hidden\" name=\"status\" value=\"VALID\" />
        <input type=\"hidden\" name=\"amount\" value=\"{amount}\" />
        <input type=\"hidden\" name=\"currency\" value=\"{currency}\" />
        <input type=\"hidden\" name=\"value_a\" value=\"{uid}\" />
        <input type=\"hidden\" name=\"value_b\" value=\"{plan}\" />
        <button type=\"submit\" class=\"btn btn-primary\">Pay Now</button>
      </form>
      <form class=\"actions\" method=\"POST\" action=\"/api/payment/cancel\" style=\"margin-top:0;\">
        <input type=\"hidden\" name=\"tran_id\" value=\"{transaction_id}\" />
        <input type=\"hidden\" name=\"status\" value=\"CANCELLED\" />
        <input type=\"hidden\" name=\"amount\" value=\"{amount}\" />
        <input type=\"hidden\" name=\"currency\" value=\"{currency}\" />
        <input type=\"hidden\" name=\"value_a\" value=\"{uid}\" />
        <input type=\"hidden\" name=\"value_b\" value=\"{plan}\" />
        <button type=\"submit\" class=\"btn btn-secondary\">Cancel</button>
      </form>
      <div class=\"meta\">No real charge will be made. Click Pay Now to activate premium.</div>
    </div>
  </div>
</body>
</html>"""