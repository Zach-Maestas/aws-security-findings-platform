from typing import Any

from pydantic import ValidationError

from findings_platform.core.exceptions import InvalidEventError
from findings_platform.core.validation import safe_field_errors
from findings_platform.schemas.event import CloudTrailEvent


def parse_event(raw: dict[str, Any]) -> CloudTrailEvent:
    """Validate a raw CloudTrail event dict into a CloudTrailEvent.

    Raises InvalidEventError with sanitized per-field errors
    (loc/msg/type only) if validation fails.
    """
    try:
        return CloudTrailEvent.model_validate(raw)
    except ValidationError as exc:
        raise InvalidEventError(
            "CloudTrail event failed validation.",
            {"fields": safe_field_errors(exc.errors())},
        ) from exc
