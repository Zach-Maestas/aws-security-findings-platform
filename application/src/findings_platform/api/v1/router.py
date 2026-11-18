from fastapi import APIRouter

from findings_platform.api.v1 import events

router = APIRouter(prefix="/api/v1")
router.include_router(events.router)
