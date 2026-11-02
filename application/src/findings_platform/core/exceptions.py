from typing import Any


class AppError(Exception):
    """Base for expected errors; the API maps each one to the error response shape."""

    status_code: int = 500
    code: str = "internal_error"

    def __init__(self, message: str, details: dict[str, Any] | None = None):
        super().__init__(message)
        self.message = message
        self.details = details


class FindingNotFoundError(AppError):
    status_code = 404
    code = "finding_not_found"


class InvalidEventError(AppError):
    status_code = 422
    code = "invalid_event"
