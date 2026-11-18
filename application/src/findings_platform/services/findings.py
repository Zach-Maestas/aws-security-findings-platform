import logging
import uuid
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from sqlalchemy import exists, select
from sqlalchemy.orm import Session

from findings_platform.models.enums import Status
from findings_platform.models.event import Event
from findings_platform.models.finding import Finding
from findings_platform.schemas.event import CloudTrailEvent
from findings_platform.services.detection.dispatch import detect
from findings_platform.services.detection.types import Detection, Ignored
from findings_platform.services.parsing import parse_event

logger = logging.getLogger(__name__)


class IngestOutcome(StrEnum):
    CREATED = "created"  # a new finding was opened
    UPDATED = "updated"  # the event attached to an existing finding
    DUPLICATE = "duplicate"  # this eventID was already stored; nothing changed
    IGNORED = "ignored"  # no detection; nothing stored


@dataclass(frozen=True)
class IngestResult:
    """What ingest did with one event. HTTP-free, so the Phase 2 consumer reuses it."""

    outcome: IngestOutcome
    finding_id: uuid.UUID | None = None
    reason: str | None = None  # the IgnoreReason, for ignored events


def ingest_event(db: Session, raw: dict[str, Any]) -> IngestResult:
    """Turn one raw CloudTrail record into a new or updated finding.

    Raises InvalidEventError (422) if the record fails validation. Everything that
    is stored (the finding and the event) is committed in one transaction.
    """
    event = parse_event(raw)

    result = detect(event)
    if isinstance(result, Ignored):
        logger.info(
            "Event ignored",
            extra={
                "event_id": event.event_id,
                "event_name": event.event_name,
                "reason": result.reason.value,
                "detail": result.detail,
            },
        )
        return IngestResult(IngestOutcome.IGNORED, reason=result.reason.value)

    if _is_duplicate(db, event.event_id):
        logger.info("Duplicate event skipped", extra={"event_id": event.event_id})
        return IngestResult(IngestOutcome.DUPLICATE)

    finding = _find_matchable_finding(db, result.fingerprint)
    if finding is None:
        finding = _create_finding(result, event)
        db.add(finding)
        outcome = IngestOutcome.CREATED
    else:
        _update_finding(finding, result, event)
        outcome = IngestOutcome.UPDATED

    db.add(_build_event(event, raw, finding))
    db.commit()

    logger.info(
        "Event ingested",
        extra={
            "event_id": event.event_id,
            "outcome": outcome.value,
            "finding_id": str(finding.id),
            "detection_type": result.detection_type.value,
            "severity": result.severity.value,
        },
    )
    return IngestResult(outcome, finding_id=finding.id)


def _is_duplicate(db: Session, cloudtrail_event_id: str) -> bool:
    """True if an Event with this CloudTrail eventID is already stored."""
    stmt = select(exists().where(Event.cloudtrail_event_id == cloudtrail_event_id))
    return bool(db.scalar(stmt))


def _find_matchable_finding(db: Session, fingerprint: str) -> Finding | None:
    """The OPEN or SUPPRESSED finding with this fingerprint, if any.

    RESOLVED findings never match: a recurrence opens a new finding.
    """
    stmt = select(Finding).where(
        Finding.fingerprint == fingerprint,
        Finding.status.in_([Status.OPEN, Status.SUPPRESSED]),
    )
    return db.execute(stmt).scalar_one_or_none()


def _create_finding(detection: Detection, event: CloudTrailEvent) -> Finding:
    """A new OPEN finding from the detection, last seen at the event's time."""
    return Finding(
        fingerprint=detection.fingerprint,
        detection_type=detection.detection_type,
        severity=detection.severity,
        resource=detection.resource,
        account=detection.account,
        region=detection.region,
        last_seen_at=event.event_time,
    )


def _update_finding(
    finding: Finding, detection: Detection, event: CloudTrailEvent
) -> None:
    """Apply a matching event to an existing finding.

    Severity only rises, last_seen_at only moves forward (events can arrive out of
    order), and status is left alone (a SUPPRESSED finding stays suppressed).
    """
    if detection.severity.rank > finding.severity.rank:
        finding.severity = detection.severity

    if event.event_time > finding.last_seen_at:
        finding.last_seen_at = event.event_time


def _build_event(
    event: CloudTrailEvent, raw: dict[str, Any], finding: Finding
) -> Event:
    """The Event row for a stored CloudTrail record, linked to its finding."""
    identity = event.user_identity
    return Event(
        cloudtrail_event_id=event.event_id,
        finding=finding,
        event_name=event.event_name,
        event_time=event.event_time,
        actor_type=identity.identity_type,
        # AWS-service calls have no ARN; invokedBy names the service instead.
        actor=identity.arn or identity.invoked_by or "unknown",
        source_ip=event.source_ip_address,
        raw_event=raw,
    )
