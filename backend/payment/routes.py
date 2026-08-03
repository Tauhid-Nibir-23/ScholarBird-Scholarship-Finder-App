"""FastAPI routes for the payment foundation."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from .models import PaymentCallbackPayload, PaymentCreateRequest, PaymentCreateResponse, PaymentValidationRequest, PaymentValidationResponse, SandboxPaymentCreateRequest
from .service import DuplicateTransactionError, PaymentError, PaymentService

router = APIRouter(prefix="/api/payment", tags=["payment"])
sandbox_router = APIRouter(prefix="/payment", tags=["payment"])
_service: PaymentService | None = None


def get_payment_service() -> PaymentService:
    """Create the payment service lazily so imports do not require env setup."""
    global _service
    if _service is None:
        _service = PaymentService()
    return _service


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

