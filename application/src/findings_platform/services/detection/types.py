from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from findings_platform.models.enums import DetectionType, Severity
from findings_platform.schemas.event import CloudTrailEvent


@dataclass(frozen=True)
class Detection:
    """What a handler found: everything ingest needs to create or update a finding."""

    detection_type: DetectionType
    severity: Severity
    fingerprint: str
    resource: str
    account: str
    region: str | None


class IgnoreReason(StrEnum):
    ERROR_CODE = "error_code"
    UNHANDLED_EVENT_NAME = "unhandled_event_name"
    NOT_RISKY = "not_risky"


@dataclass(frozen=True)
class Ignored:
    """An event that produced no detection, and which rule caused that."""

    reason: IgnoreReason
    detail: str | None = None


Handler = Callable[[CloudTrailEvent], Detection | None]
