from collections.abc import Generator
from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from findings_platform.db.session import SessionLocal


def get_db() -> Generator[Session]:
    with SessionLocal() as session:
        yield session


# FastAPI calls get_db() on each request and passes the session to the endpoint.
DbSession = Annotated[Session, Depends(get_db)]
