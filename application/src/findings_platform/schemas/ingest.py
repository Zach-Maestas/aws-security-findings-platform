import uuid

from pydantic import BaseModel

from findings_platform.services.findings import IngestOutcome


class IngestResponse(BaseModel):
    """What happened to an ingested event."""

    outcome: IngestOutcome
    finding_id: uuid.UUID | None = None
    reason: str | None = None
