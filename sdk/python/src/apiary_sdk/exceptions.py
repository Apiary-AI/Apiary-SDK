"""Error types mapped from the Apiary API envelope."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class ApiError:
    """A single error entry from the API ``errors`` array."""

    message: str
    code: str
    field: str | None = None


class ApiaryError(Exception):
    """Base exception for all Apiary SDK errors."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int = 0,
        errors: list[ApiError] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.errors = errors or []


class ValidationError(ApiaryError):
    """422 — one or more fields failed validation."""


class AuthenticationError(ApiaryError):
    """401 — invalid or missing credentials."""


class PermissionError(ApiaryError):  # noqa: N818 — shadows builtin intentionally
    """403 — insufficient permissions."""


class NotFoundError(ApiaryError):
    """404 — resource does not exist."""


class ConflictError(ApiaryError):
    """409 — resource state conflict (e.g. task already claimed)."""


_STATUS_MAP: dict[int, type[ApiaryError]] = {
    401: AuthenticationError,
    403: PermissionError,
    404: NotFoundError,
    409: ConflictError,
    422: ValidationError,
}


def _parse_errors(errors_raw) -> list[ApiError]:
    """Normalise the ``errors`` value from an API envelope into a list of :class:`ApiError`.

    Handles two shapes:
    - **list** of error objects: ``[{"message": "...", "code": "...", "field": "..."}]``
    - **dict** mapping field names to messages (Laravel validation style):
      ``{"name": ["The name field is required."], "email": "Must be valid."}``
    """
    if isinstance(errors_raw, list):
        return [
            ApiError(
                message=e.get("message", "Unknown error") if isinstance(e, dict) else str(e),
                code=e.get("code", "unknown") if isinstance(e, dict) else "unknown",
                field=e.get("field") if isinstance(e, dict) else None,
            )
            for e in errors_raw
        ]

    if isinstance(errors_raw, dict):
        errors: list[ApiError] = []
        for field_name, messages in errors_raw.items():
            if isinstance(messages, list):
                for msg in messages:
                    errors.append(
                        ApiError(message=str(msg), code="validation_error", field=field_name)
                    )
            else:
                errors.append(
                    ApiError(message=str(messages), code="validation_error", field=field_name)
                )
        return errors

    return []


def raise_for_status(status_code: int, body: dict) -> None:
    """Raise the appropriate :class:`ApiaryError` subclass for an error response."""
    errors = _parse_errors(body.get("errors"))
    message = errors[0].message if errors else f"HTTP {status_code}"
    exc_cls = _STATUS_MAP.get(status_code, ApiaryError)
    raise exc_cls(message, status_code=status_code, errors=errors)
