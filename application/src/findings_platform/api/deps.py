from collections.abc import Generator
from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from findings_platform.db.session import SessionLocal


def get_db() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session


DbSession = Annotated[
    Session, Depends(get_db)
]  # FastAPI reads metadata at runtime; it will call get_db() on each request and pass result as 'db'.
