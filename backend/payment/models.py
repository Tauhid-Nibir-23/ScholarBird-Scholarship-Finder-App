"""Typed request and response models for SSLCommerz payment APIs."""

from __future__ import annotations

from enum import Enum
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, HttpUrl


class PaymentStatus(str, Enum):
    """Supported payment states returned by the payment module."""

    PENDING = "PENDING"
    VALID = "VALID"
    VALIDATED = "VALIDATED"
    INVALID = "INVALID"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"


class CustomerInfo(BaseModel):
    """Customer profile data sent to SSLCommerz for checkout."""

    name: str = Field(min_length=1, max_length=50)
    email: str = Field(min_length=1, max_length=50)
    address_line_1: str = Field(alias="address1", min_length=1, max_length=50)
    address_line_2: str = Field(default="Dhaka", alias="address2", max_length=50)
    city: str = Field(min_length=1, max_length=50)
    state: str = Field(default="Dhaka", max_length=50)
    postcode: str = Field(default="1000", max_length=30)
    country: str = Field(default="Bangladesh", max_length=50)
    phone: str = Field(min_length=1, max_length=20)
    fax: str = Field(default="", max_length=20)


class ShippingInfo(BaseModel):
    """Shipping details passed through to SSLCommerz."""

    name: str = Field(min_length=1, max_length=50)
    address_line_1: str = Field(alias="address1", min_length=1, max_length=50)
    address_line_2: str = Field(default="Dhaka", alias="address2", max_length=50)
    city: str = Field(min_length=1, max_length=50)
    state: str = Field(default="Dhaka", max_length=50)
    postcode: str = Field(default="1000", max_length=50)
    country: str = Field(default="Bangladesh", max_length=50)


class PaymentCreateRequest(BaseModel):
    """Payload accepted by ``POST /api/payment/create``."""

    uid: str = Field(min_length=1, max_length=128)
    subscription_plan: str = Field(min_length=1, max_length=32)
    total_amount: float = Field(gt=0)
    currency: str = Field(default="BDT", min_length=3, max_length=3)
    customer: CustomerInfo
    shipping: Optional[ShippingInfo] = None
    value_a: str = Field(default="", max_length=255)
    value_b: str = Field(default="", max_length=255)
    value_c: str = Field(default="", max_length=255)
    value_d: str = Field(default="", max_length=255)
    success_url: Optional[HttpUrl] = None
    fail_url: Optional[HttpUrl] = None
    cancel_url: Optional[HttpUrl] = None
    ipn_url: Optional[HttpUrl] = None


class PaymentCreateResponse(BaseModel):
    """Public response returned after session creation."""

    gateway_url: str
    transaction_id: str


class SandboxPaymentCreateRequest(BaseModel):
    """Minimal payload accepted by ``POST /payment/create``."""

    uid: str = Field(min_length=1, max_length=128)
    plan: str = Field(min_length=1, max_length=32)
    amount: float = Field(gt=0)


class PaymentValidationRequest(BaseModel):
    """Payload accepted by ``POST /api/payment/validate``."""

    transaction_id: Optional[str] = Field(default=None, max_length=64)
    val_id: Optional[str] = Field(default=None, max_length=128)
    session_key: Optional[str] = Field(default=None, max_length=128)


class PaymentValidationResponse(BaseModel):
    """Validation status returned by the backend."""

    status: str
    transaction_id: str
    validation_id: Optional[str] = None
    amount: Optional[str] = None
    currency: Optional[str] = None
    raw: Dict[str, Any] = Field(default_factory=dict)


class PaymentCallbackPayload(BaseModel):
    """Generic callback body for success, fail, cancel, and IPN routes."""

    transaction_id: Optional[str] = Field(default=None, alias="tran_id", max_length=64)
    val_id: Optional[str] = Field(default=None, max_length=128)
    status: Optional[str] = Field(default=None, max_length=32)
    amount: Optional[str] = Field(default=None, max_length=32)
    currency: Optional[str] = Field(default=None, max_length=16)
    sessionkey: Optional[str] = Field(default=None, max_length=128)
    uid: Optional[str] = Field(default=None, alias="value_a", max_length=128)
    plan: Optional[str] = Field(default=None, alias="value_b", max_length=32)
    gateway_response: Dict[str, Any] = Field(default_factory=dict)
