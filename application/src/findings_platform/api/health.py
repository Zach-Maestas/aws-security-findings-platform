from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    return {"status": "ok"}


@router.get("/ready")
def ready():
    # TODO (1.2): check the database connection; return 503 if it fails
    return {"status": "ready"}
