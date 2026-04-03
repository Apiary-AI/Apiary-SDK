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
from apiary_sdk.large_result import LARGE_RESULT_THRESHOLD_BYTES, LargeResultDelivery
from apiary_sdk.service_worker import OperationNotFoundError, ServiceWorker
from apiary_sdk.streaming import StreamingTask

__version__ = "0.1.0"

__all__ = [
    "ApiaryClient",
    "ApiaryError",
    "AuthenticationError",
    "ApiaryPermissionError",
    "ConflictError",
    "LARGE_RESULT_THRESHOLD_BYTES",
    "LargeResultDelivery",
    "NotFoundError",
    "OperationNotFoundError",
    "ServiceWorker",
    "StreamingTask",
    "ValidationError",
    "__version__",
]
