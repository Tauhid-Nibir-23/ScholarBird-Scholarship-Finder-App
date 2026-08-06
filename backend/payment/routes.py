"""FastAPI routes for the payment foundation."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import HTMLResponse

from .mock_gateway import MockGatewayService
from .models import (
    PaymentCallbackPayload,
    PaymentCreateRequest,
    PaymentCreateResponse,
    PaymentValidationRequest,
    PaymentValidationResponse,
    SandboxPaymentCreateRequest,
)
from .service import (
    DuplicateTransactionError,
    PaymentError,
    PaymentService,
    resolve_gateway_name,
)

router = APIRouter(prefix="/api/payment", tags=["payment"])
sandbox_router = APIRouter(prefix="/payment", tags=["payment"])
checkout_router = APIRouter(tags=["payment"])
_service: PaymentService | None = None


def get_payment_service() -> PaymentService:
    """Create the payment service lazily so imports do not require env setup."""
    global _service
    if _service is None:
        _service = PaymentService()
    return _service


def _active_mock_service() -> MockGatewayService | None:
    """Return the in-memory mock service when the mock gateway is active."""
    if resolve_gateway_name() != "mock":
        return None
    service = get_payment_service()
    impl = getattr(service, "_impl", None)
    return impl if isinstance(impl, MockGatewayService) else None


@checkout_router.get("/payment/mock-checkout", response_class=HTMLResponse)
async def mock_checkout_page(request: Request) -> HTMLResponse:
    """Render the dev-only mock checkout page."""
    mock = _active_mock_service()
    if mock is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mock checkout is only available when PAYMENT_GATEWAY=mock",
        )
    params = dict(request.query_params)
    return HTMLResponse(content=mock.render_checkout_page(params))


@checkout_router.get("/payment/gateway-info")
def gateway_info() -> dict[str, str]:
    """Expose the active gateway name for diagnostics."""
    return {"gateway": resolve_gateway_name()}


@router.post("/create", response_model=PaymentCreateResponse)
def create_payment(request: PaymentCreateRequest) -> PaymentCreateResponse:
    """Create a payment session with SSLCommerz."""
    try:
        return get_payment_service().create_payment(request)
    except DuplicateTransactionError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except PaymentError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@sandbox_router.post("/create", response_model=PaymentCreateResponse)
def create_sandbox_payment(
    request: SandboxPaymentCreateRequest,
) -> PaymentCreateResponse:
    """Create an SSLCommerz Sandbox checkout session."""
    try:
        return get_payment_service().create_sandbox_payment(request)
    except PaymentError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@router.post("/validate", response_model=PaymentValidationResponse)
def validate_payment(request: PaymentValidationRequest) -> PaymentValidationResponse:
    """Validate a transaction using SSLCommerz validation API."""
    try:
        return get_payment_service().validate_payment(request)
    except PaymentError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@router.post("/success")
def payment_success(payload: PaymentCallbackPayload) -> dict[str, str]:
    """Receive a success callback from SSLCommerz."""
    return get_payment_service().handle_callback("success", payload)


@router.post("/direct-activate")
def direct_activate_subscription(payload: dict[str, Any]) -> dict[str, Any]:
    """Skip the gateway entirely and activate premium for the current user.

    Used by the Flutter app's demo / non-SSLCommerz upgrade flow: the client
    only needs to send the Firebase ``uid`` and selected ``plan``. The backend
    records a synthetic transaction, writes Firestore via SubscriptionManager,
    and returns the resulting subscription state. No payment gateway is hit.
    """
    uid = str(payload.get("uid") or "").strip()
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="uid is required"
        )
    plan = str(payload.get("plan") or "monthly").strip().lower()
    amount = float(payload.get("amount") or 0.0)
    currency = str(payload.get("currency") or "BDT").strip() or "BDT"

    from .subscription import SubscriptionManager

    manager = SubscriptionManager()
    result = manager.activate_or_extend_subscription(
        uid=uid,
        plan=plan,
        gateway="direct",
        payment_id="DIRECT_ACTIVATE",
        transaction_id=f"DIRECT_{uid}_{plan}".upper(),
        amount=amount,
        currency=currency,
        status="DIRECT_ACTIVATED",
    )
    return {
        "status": "premium",
        "subscription": manager.get_subscription_state(uid),
        "raw": {k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in result.items()},
    }


@router.post("/fail")
def payment_fail(payload: PaymentCallbackPayload) -> dict[str, str]:
    """Receive a fail callback from SSLCommerz."""
    return get_payment_service().handle_callback("fail", payload)


@router.post("/cancel")
def payment_cancel(payload: PaymentCallbackPayload) -> dict[str, str]:
    """Receive a cancel callback from SSLCommerz."""
    return get_payment_service().handle_callback("cancel", payload)


@router.post("/ipn")
def payment_ipn(payload: PaymentCallbackPayload) -> dict[str, str]:
    """Receive an IPN callback from SSLCommerz."""
    return get_payment_service().handle_callback("ipn", payload)


@router.get("/subscription/{uid}")
def get_subscription_status(uid: str) -> dict[str, Any]:
    """Read-only validation endpoint to refresh user subscription status (max 1 Firestore read)."""
    from .subscription import SubscriptionManager
    manager = SubscriptionManager()
    return manager.get_subscription_state(uid)


@router.post("/admin/grant")
def admin_grant_subscription(payload: dict[str, Any]) -> dict[str, Any]:
    """Admin endpoint to manually grant premium status without payment."""
    uid = str(payload.get("uid") or "").strip()
    if not uid:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="uid is required")
    plan = str(payload.get("plan") or "monthly")
    custom_days = payload.get("custom_days")
    days_int = int(custom_days) if custom_days is not None else None

    from .subscription import SubscriptionManager
    manager = SubscriptionManager()
    return manager.grant_admin_override(uid=uid, plan=plan, custom_days=days_int)


@router.post("/admin/revoke")
def admin_revoke_subscription(payload: dict[str, Any]) -> dict[str, Any]:
    """Admin endpoint to manually revoke premium status without deleting payment history."""
    uid = str(payload.get("uid") or "").strip()
    if not uid:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="uid is required")

    from .subscription import SubscriptionManager
    manager = SubscriptionManager()
    return manager.revoke_admin_override(uid=uid)

