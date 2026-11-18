from typing import Annotated, Any

from fastapi import APIRouter, Body, Response, status

from findings_platform.api.deps import DbSession
from findings_platform.schemas.ingest import IngestResponse
from findings_platform.services.findings import IngestOutcome, ingest_event

router = APIRouter(prefix="/events", tags=["events"])


@router.post("", response_model=IngestResponse)
def ingest(
    raw: Annotated[dict[str, Any], Body()],
    db: DbSession,
    response: Response,
) -> IngestResponse:
    """Ingest one CloudTrail record.

    The body is taken as a raw dict and validated by the service, so a malformed
    record gets the sanitized 422 invalid_event error instead of echoing input back.
    """
    result = ingest_event(db, raw)
    if result.outcome is IngestOutcome.CREATED:
        response.status_code = status.HTTP_201_CREATED
    return IngestResponse(
        outcome=result.outcome,
        finding_id=result.finding_id,
        reason=result.reason,
    )
