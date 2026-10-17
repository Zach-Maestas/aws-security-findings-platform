from fastapi import FastAPI

from findings_platform.api import health
from findings_platform.core.config import settings
from findings_platform.core.logging_config import configure_logging

configure_logging(settings.log_level)
app = FastAPI(title=settings.app_name)

app.include_router(health.router)
