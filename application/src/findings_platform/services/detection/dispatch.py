from findings_platform.schemas.event import CloudTrailEvent
from findings_platform.services.detection.types import (
    Detection,
    Handler,
    Ignored,
    IgnoreReason,
)

HANDLERS: dict[str, Handler] = {}


def detect(event: CloudTrailEvent) -> Detection | Ignored:
    """Run the matching handler for this event, or explain why none applied."""
    if event.error_code:
        return Ignored(IgnoreReason.ERROR_CODE, detail=event.error_code)

    handler = HANDLERS.get(event.event_name)
    if handler is None:
        return Ignored(IgnoreReason.UNHANDLED_EVENT_NAME, detail=event.event_name)

    detection = handler(event)
    if detection is None:
        return Ignored(IgnoreReason.NOT_RISKY)
    return detection
