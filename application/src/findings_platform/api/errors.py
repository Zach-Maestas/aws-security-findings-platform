"""Map every exception to the API's single error shape (see docs/api.md)."""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from findings_platform.core.exceptions import AppError
from findings_platform.schemas.errors import ErrorDetail, ErrorResponse

logger = logging.getLogger(__name__)

_HTTP_ERROR_CODES: dict[int, str] = {
    404: "not_found",
    405: "method_not_allowed",
    503: "service_unavailable",
}


def _error_response(
    status_code: int, code: str, message: str, details: dict[str, Any] | None = None
) -> JSONResponse:
    body = ErrorResponse(error=ErrorDetail(code=code, message=message, details=details))
    return JSONResponse(status_code=status_code, content=body.model_dump())


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request, exc):
        return _error_response(exc.status_code, exc.code, exc.message, exc.details)

    @app.exception_handler(RequestValidationError)  # FastAPI's automatic 422s
    async def handle_validation_error(request: Request, exc: AppError):
        # Keep only loc/msg/type; "input" would echo the client's raw data back.
        fields = [
            {key: err[key] for key in ("loc", "msg", "type")} for err in exc.errors()
        ]

        return _error_response(
            status_code=422,
            code="validation_error",
            message="Request validation failed.",
            details={"fields": fields},
        )

    # Starlette's class also covers FastAPI's HTTPException and routing 404s/405s.
    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(request: Request, exc: StarletteHTTPException):
        code = _HTTP_ERROR_CODES.get(exc.status_code, "http_error")
        return _error_response(
            status_code=exc.status_code,
            code=code,
            message=str(exc.detail),
        )

    @app.exception_handler(Exception)  # anything unexpected becomes a 500
    async def handle_unexpected_error(request: Request, exc: Exception):
        logger.exception("Unhandled error", extra={"path": request.url.path})
        return _error_response(
            status_code=500,
            code="internal_error",
            # Never return str(exc): it can leak internals.
            # The traceback is logged instead.
            message="An unexpected error occurred.",
        )
