import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, DateTime, Index, func, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from findings_platform.db.base import Base
from findings_platform.models.enums import (
    DetectionType,
    Severity,
    Status,
    SuppressionReason,
)

if TYPE_CHECKING:
    from findings_platform.models.event import Event


class Finding(Base):
    """One problem, identified by its fingerprint. See docs/data-model.md."""

    __tablename__ = "findings"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    detection_type: Mapped[DetectionType] = mapped_column()
    # Only rises: a matching event sets it to the higher of the two.
    severity: Mapped[Severity] = mapped_column()
    events: Mapped[list["Event"]] = relationship(
        back_populates="finding",
        order_by="Event.event_time",
    )
    status: Mapped[Status] = mapped_column(server_default="OPEN")
    # "{DETECTION_TYPE}|{normalized ARN}[|...]", stored as plain text for debugging.
    fingerprint: Mapped[str] = mapped_column()
    # account and region are copies of values in the resource ARN, kept for filtering.
    account: Mapped[str] = mapped_column()
    # NULL only for IAM findings, since IAM resources are global.
    region: Mapped[str | None] = mapped_column()
    # Normalized ARN of the affected resource (the principal for ADMIN_ACCESS_GRANTED).
    resource: Mapped[str] = mapped_column()
    suppression_reason: Mapped[SuppressionReason | None] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    # onupdate is applied by SQLAlchemy, not a DB trigger; raw SQL updates skip it.
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    # Set by ingest from the matching event, so no server default.
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        # At most one matchable (OPEN or SUPPRESSED) finding per fingerprint, even
        # under concurrent ingest. RESOLVED rows are excluded so a recurrence can
        # open a new finding. Also serves the ingest lookup by fingerprint.
        Index(
            "uq_findings_fingerprint_matchable",
            "fingerprint",
            unique=True,
            postgresql_where=text("status IN ('OPEN', 'SUPPRESSED')"),
        ),
        # Each CHECK below is a biconditional: the column is set exactly when the
        # condition holds, never otherwise.
        # suppression_reason is present exactly when SUPPRESSED.
        CheckConstraint(
            "(status = 'SUPPRESSED') = (suppression_reason IS NOT NULL)",
            name="ck_findings_suppressed_has_reason",
        ),
        # resolved_at is present exactly when RESOLVED.
        CheckConstraint(
            "(status = 'RESOLVED') = (resolved_at IS NOT NULL)",
            name="ck_findings_resolved_has_resolved_at",
        ),
        # region is NULL exactly for IAM (global) findings.
        CheckConstraint(
            "(detection_type = 'ADMIN_ACCESS_GRANTED') = (region IS NULL)",
            name="ck_findings_region_null_only_for_admin",
        ),
    )
