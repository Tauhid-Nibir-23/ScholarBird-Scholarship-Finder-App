"""Core SSLCommerz payment service."""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Any, Mapping

import httpx

from backend.core.exceptions import ScholarBirdError

from .models import PaymentCallbackPayload, PaymentCreateRequest, PaymentCreateResponse, PaymentStatus, PaymentValidationRequest, PaymentValidationResponse, SandboxPaymentCreateRequest
from .utils import generate_transaction_id, normalize_amount, safe_log_payload

logger = logging.getLogger(__name__)


class PaymentError(ScholarBirdError):
    """Raised when a payment operation fails."""


class DuplicateTransactionError(PaymentError):
    """Raised when the same transaction id is created twice."""


@dataclass(frozen=True)
class SSLCommerzConfig:
    """Runtime SSLCommerz configuration loaded from environment variables."""

    store_id: str
    store_password: str
    sandbox: bool
    api_url: str
    validation_api_url: str

    @classmethod
    def from_env(cls) -> "SSLCommerzConfig":
        store_id = os.getenv("SSLCOMMERZ_STORE_ID", "").strip()
        store_password = os.getenv("SSLCOMMERZ_STORE_PASSWORD", "").strip()
        sandbox = os.getenv("SSLCOMMERZ_SANDBOX", "true").strip().lower() in {"1", "true", "yes", "on"}
        api_url = os.getenv("SSLCOMMERZ_API", "https://sandbox.sslcommerz.com/gwprocess/v4/api.php").strip()
        validation_api_url = os.getenv(
            "SSLCOMMERZ_VALIDATION_API",
            "https://sandbox.sslcommerz.com/validator/api/validationserverAPI.php",
        ).strip()

        if not store_id or not store_password:
            raise PaymentError("SSLCommerz credentials are missing from the environment")
        return cls(
            store_id=store_id,
            store_password=store_password,
            sandbox=sandbox,
            api_url=api_url,
            validation_api_url=validation_api_url,
        )


class PaymentService:
    """Encapsulates SSLCommerz session creation and validation."""

    def __init__(self, config: SSLCommerzConfig | None = None) -> None:
        self._config = config or SSLCommerzConfig.from_env()
        self._transactions: dict[str, dict[str, Any]] = {}

    def create_payment(self, request: PaymentCreateRequest) -> PaymentCreateResponse:
        """Create an SSLCommerz payment session and return the hosted URL."""
        transaction_id = generate_transaction_id(request.uid, request.subscription_plan)
        if transaction_id in self._transactions:
            raise DuplicateTransactionError(f"Duplicate transaction id generated: {transaction_id}")

        callback_base = self._resolve_callback_base(request)
        payload = {
            "store_id": self._config.store_id,
            "store_passwd": self._config.store_password,
            "total_amount": normalize_amount(request.total_amount),
            "currency": request.currency,
            "tran_id": transaction_id,
            "product_category": "subscription",
            "success_url": str(request.success_url or f"{callback_base}/api/payment/success"),
            "fail_url": str(request.fail_url or f"{callback_base}/api/payment/fail"),
            "cancel_url": str(request.cancel_url or f"{callback_base}/api/payment/cancel"),
            "ipn_url": str(request.ipn_url or f"{callback_base}/api/payment/ipn"),
            "cus_name": request.customer.name,
            "cus_email": request.customer.email,
            "cus_add1": request.customer.address_line_1,
            "cus_add2": request.customer.address_line_2,
            "cus_city": request.customer.city,
            "cus_state": request.customer.state,
            "cus_postcode": request.customer.postcode,
            "cus_country": request.customer.country,
            "cus_phone": request.customer.phone,
            "cus_fax": request.customer.fax,
            "ship_name": (request.shipping.name if request.shipping else request.customer.name),
            "ship_add1": (request.shipping.address_line_1 if request.shipping else request.customer.address_line_1),
            "ship_add2": (request.shipping.address_line_2 if request.shipping else request.customer.address_line_2),
            "ship_city": (request.shipping.city if request.shipping else request.customer.city),
            "ship_state": (request.shipping.state if request.shipping else request.customer.state),
            "ship_postcode": (request.shipping.postcode if request.shipping else request.customer.postcode),
            "ship_country": (request.shipping.country if request.shipping else request.customer.country),
            "shipping_method": "NO",
            "num_of_item": "1",
            "product_name": f"ScholarBird {request.subscription_plan}",
            "product_profile": "non-physical-goods",
            "product_category": "subscription",
            "value_a": request.uid,
            "value_b": request.subscription_plan,
            "value_c": request.value_c,
            "value_d": request.value_d,
        }

        logger.info("Creating payment session: %s", safe_log_payload(payload))
        try:
            response = self._post_session(payload)
        except httpx.TimeoutException as exc:
            logger.exception("Payment session creation timed out: %s", transaction_id)
            raise PaymentError("Payment session creation timed out") from exc
        except httpx.HTTPError as exc:
            logger.exception("Payment session creation failed: %s", transaction_id)
            raise PaymentError("Payment session creation failed") from exc

        gateway_url = response.get("GatewayPageURL") or response.get("redirectGatewayURL")
        if not gateway_url:
            raise PaymentError("SSLCommerz returned an invalid session response")

        self._transactions[transaction_id] = {
            "request": request.model_dump(),
            "session": response,
            "status": PaymentStatus.PENDING.value,
        }
        return PaymentCreateResponse(gateway_url=str(gateway_url), transaction_id=transaction_id)

    def create_sandbox_payment(
        self, request: SandboxPaymentCreateRequest
    ) -> PaymentCreateResponse:
        """Create a minimal SSLCommerz Sandbox checkout session."""
        if os.getenv("SSLCOMMERZ_IS_SANDBOX", "").strip().lower() not in {
            "1", "true", "yes", "on"
        }:
            raise PaymentError("SSLCOMMERZ_IS_SANDBOX must be true")

        transaction_id = generate_transaction_id(request.uid, request.plan)
        payload = {
            "store_id": self._config.store_id,
            "store_passwd": self._config.store_password,
            "total_amount": normalize_amount(request.amount),
            "currency": "BDT",
            "tran_id": transaction_id,
            "success_url": "http://localhost:8000/api/payment/success",
            "fail_url": "http://localhost:8000/api/payment/fail",
            "cancel_url": "http://localhost:8000/api/payment/cancel",
            "shipping_method": "NO",
            "product_name": f"ScholarBird {request.plan}",
            "product_category": "subscription",
            "product_profile": "non-physical-goods",
            "cus_name": request.uid,
            "cus_email": "customer@scholarbird.local",
            "cus_add1": "Dhaka",
            "cus_city": "Dhaka",
            "cus_country": "Bangladesh",
            "cus_phone": "01700000000",
            "value_a": request.uid,
            "value_b": request.plan,
        }
        try:
            response = self._post_sandbox_session(payload)
        except httpx.TimeoutException as exc:
            raise PaymentError("Payment session creation timed out") from exc
        except httpx.HTTPError as exc:
            raise PaymentError("Payment session creation failed") from exc

        gateway_url = response.get("GatewayPageURL") or response.get("redirectGatewayURL")
        if not gateway_url:
            raise PaymentError("SSLCommerz returned an invalid session response")
        self._transactions[transaction_id] = {
            "uid": request.uid,
            "plan": request.plan,
            "amount": request.amount,
        }
        return PaymentCreateResponse(
            gateway_url=str(gateway_url), transaction_id=transaction_id
        )

    def validate_payment(self, request: PaymentValidationRequest) -> PaymentValidationResponse:
        """Validate a payment by transaction id or validation id."""
        reference_id = request.val_id or request.transaction_id or request.session_key
        if not reference_id:
            raise PaymentError("A transaction id, val_id, or session key is required")

        payload = {
            "val_id": request.val_id,
            "tran_id": request.transaction_id,
            "sessionkey": request.session_key,
            "store_id": self._config.store_id,
            "store_passwd": self._config.store_password,
            "format": "json",
        }
        logger.info("Validating payment: %s", safe_log_payload(payload))
        try:
            response = self._get_validation(payload)
        except httpx.TimeoutException as exc:
            logger.exception("Payment validation timed out: %s", reference_id)
            raise PaymentError("Payment validation timed out") from exc
        except httpx.HTTPError as exc:
            logger.exception("Payment validation failed: %s", reference_id)
            raise PaymentError("Payment validation failed") from exc

        status = str(response.get("status", "FAILED"))
        transaction_id = str(response.get("tran_id") or request.transaction_id or "")
        if not transaction_id:
            raise PaymentError("SSLCommerz returned a response without a transaction id")

        self._transactions.setdefault(transaction_id, {})["validation"] = response
        self._transactions[transaction_id]["status"] = status

        if status.upper() in {"VALID", "VALIDATED"}:
            tx_data = self._transactions.get(transaction_id, {})
            req_data = tx_data.get("request", {})
            uid = str(response.get("value_a") or req_data.get("uid") or "").strip()
            plan = str(response.get("value_b") or req_data.get("subscription_plan") or "monthly").strip()
            amount_str = str(response.get("amount") or req_data.get("total_amount") or "0.0")
            currency = str(response.get("currency") or req_data.get("currency") or "BDT")
            val_id = str(response.get("val_id") or "")

            if uid:
                try:
                    from .subscription import SubscriptionManager
                    manager = SubscriptionManager()
                    manager.activate_or_extend_subscription(
                        uid=uid,
                        plan=plan,
                        gateway="sslcommerz",
                        payment_id=val_id,
                        transaction_id=transaction_id,
                        amount=float(amount_str),
                        currency=currency,
                        status=status.upper(),
                    )
                except Exception as exc:
                    logger.warning("Failed to persist Firestore subscription for %s: %s", uid, exc)

        return PaymentValidationResponse(
            status=status,
            transaction_id=transaction_id,
            validation_id=response.get("val_id"),
            amount=response.get("amount"),
            currency=response.get("currency"),
            raw=response,
        )

    def handle_callback(self, route_name: str, payload: PaymentCallbackPayload) -> dict[str, Any]:
        """Record callbacks and activate subscriptions only after a success callback."""
        transaction_id = payload.transaction_id or payload.sessionkey or payload.val_id or ""
        logger.info("Received %s callback: %s", route_name, safe_log_payload(payload.model_dump(mode="json")))
        if transaction_id:
            self._transactions.setdefault(transaction_id, {})[f"callback_{route_name}"] = payload.model_dump(mode="json")
            self._transactions[transaction_id]["status"] = (payload.status or route_name).upper()

        if route_name == "success":
            transaction = self._transactions.get(transaction_id, {})
            uid = (payload.uid or transaction.get("uid") or "").strip()
            plan = (payload.plan or transaction.get("plan") or "monthly").strip()
            if not uid:
                raise PaymentError("SSLCommerz success callback is missing the user id")

            from .subscription import SubscriptionManager

            SubscriptionManager().activate_or_extend_subscription(
                uid=uid,
                plan=plan,
                gateway="sslcommerz",
                payment_id=payload.val_id or transaction_id,
                transaction_id=transaction_id,
                amount=float(payload.amount or transaction.get("amount") or 0),
                currency=payload.currency or "BDT",
                status="VALIDATED",
            )
        return {
            "status": "accepted",
            "route": route_name,
            "transaction_id": transaction_id,
        }

    def _resolve_callback_base(self, request: PaymentCreateRequest) -> str:
        if request.success_url:
            return str(request.success_url).rsplit("/api/payment/success", 1)[0]
        return "http://localhost:8000"

    def _post_session(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        timeout = httpx.Timeout(30.0)
        with httpx.Client(timeout=timeout) as client:
            response = client.post(self._config.api_url, data=payload)
            response.raise_for_status()
            data = response.json()
        if not isinstance(data, dict):
            raise PaymentError("SSLCommerz session API returned an invalid payload")
        return data

    def _post_sandbox_session(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        """Call the fixed Sandbox endpoint; production URLs are unsupported."""
        timeout = httpx.Timeout(30.0)
        with httpx.Client(timeout=timeout) as client:
            response = client.post(
                "https://sandbox.sslcommerz.com/gwprocess/v4/api.php", data=payload
            )
            response.raise_for_status()
            data = response.json()
        if not isinstance(data, dict):
            raise PaymentError("SSLCommerz session API returned an invalid payload")
        return data

    def _get_validation(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        timeout = httpx.Timeout(30.0)
        validation_params = {
            key: value
            for key, value in payload.items()
            if value not in {None, ""}
        }
        with httpx.Client(timeout=timeout) as client:
            response = client.get(self._config.validation_api_url, params=validation_params)
            response.raise_for_status()
            data = response.json()
        if not isinstance(data, dict):
            raise PaymentError("SSLCommerz validation API returned an invalid payload")
        return data
