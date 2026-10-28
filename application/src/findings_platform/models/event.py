import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from findings_platform.db.base import Base

if TYPE_CHECKING:
    from findings_platform.models.finding import Finding


class Event(Base):
    """One CloudTrail record, linked to the finding it caused. Immutable once stored.
    See docs/data-model.md."""

    __tablename__ = "events"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    # NOT NULL: benign events are dropped, so every stored event has a finding.
    finding_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("findings.id"))
    finding: Mapped["Finding"] = relationship(back_populates="events")
    # CloudTrail's eventID; UNIQUE rejects duplicate delivery of the same event.
    cloudtrail_event_id: Mapped[str] = mapped_column(unique=True)
    event_name: Mapped[str] = mapped_column()
    # CloudTrail's eventTime, not ingest time. Drives the finding's last_seen_at.
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # CloudTrail's userIdentity.type (IAMUser, AssumedRole, Root, AWSService, ...).
    # Text, not an enum: AWS adds identity types, and an enum would reject them.
    actor_type: Mapped[str] = mapped_column()
    # userIdentity.arn, or userIdentity.invokedBy for AWSService calls (no ARN).
    # Interpret it using actor_type.
    actor: Mapped[str] = mapped_column()
    # Text, not INET: CloudTrail sends a service name (e.g. "AWS Internal")
    # instead of an IP for some calls.
    source_ip: Mapped[str] = mapped_column()
    # Full original record, kept for audit and for fields not promoted to columns.
    raw_event: Mapped[dict[str, Any]] = mapped_column(JSONB)

    __table_args__ = (
        # Postgres does not index foreign keys automatically; this serves loading
        # a finding's events.
        Index(
            "ix_events_finding_id",
            "finding_id",
        ),
    )
