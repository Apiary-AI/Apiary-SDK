"""Apiary Python SDK — minimal client for the Apiary agent orchestration platform."""

from apiary_sdk.client import ApiaryClient
from apiary_sdk.exceptions import (
    ApiaryError,
    AuthenticationError,
    ConflictError,
    NotFoundError,
    ValidationError,
)
from apiary_sdk.exceptions import PermissionError as ApiaryPermissionError

__version__ = "0.1.0"

__all__ = [
    "ApiaryClient",
    "ApiaryError",
    "AuthenticationError",
    "ApiaryPermissionError",
    "ConflictError",
    "NotFoundError",
    "ValidationError",
    "__version__",
]
