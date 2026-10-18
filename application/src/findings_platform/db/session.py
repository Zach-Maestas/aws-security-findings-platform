from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from findings_platform.core.config import settings

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(
    bind=engine,
    expire_on_commit=False,  # Ensure committed objects stay readable.
)
