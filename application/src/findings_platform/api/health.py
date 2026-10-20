import logging

from fastapi import APIRouter, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from findings_platform.api.deps import DbSession

router = APIRouter(tags=["health"])

logger = logging.getLogger(__name__)


@router.get("/health")
def health():
    return {"status": "ok"}


@router.get("/ready")
def readiness_check(db: DbSession):
    try:
        db.execute(text("SELECT 1"))
        return {"status": "ready"}
    except SQLAlchemyError as e:
        logger.warning(
            "Readiness check failed: database unavailable",
            extra={"check": "database", "error": str(e)},
        )
        raise HTTPException(status_code=503, detail="Database unavailable") from e
