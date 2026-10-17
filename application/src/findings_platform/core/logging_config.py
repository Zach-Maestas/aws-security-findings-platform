import json
import logging
import sys
from datetime import datetime, timezone

# Standard LogRecord attributes, derived from a blank record so it stays in sync
# with the Python version. Anything on a record NOT in this set came from
# `extra=` and gets emitted as a top-level JSON field. "message"/"asctime" are
# set lazily by Formatter; "color_message" is added by uvicorn.
_RESERVED = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__) | {
    "message",
    "asctime",
    "color_message",
}


class JsonFormatter(logging.Formatter):
    """Render each record as a single-line JSON object for log aggregation."""

    def format(self, record: logging.LogRecord) -> str:
        log = {
            "timestamp": datetime.fromtimestamp(
                record.created, tz=timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # add exception information to the log
        if exc_info := record.exc_info:
            log["exception"] = self.formatException(exc_info)

        # add extras passed via `logger.info(..., extra={...})`
        log |= {k: v for k, v in record.__dict__.items() if k not in _RESERVED}

        return json.dumps(log)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(stream=sys.stdout)
    handler.setFormatter(JsonFormatter())

    # Replace (not append) so repeated calls don't produce duplicate log lines.
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())

    # Route uvicorn's logs through the root JSON handler for consistent output.
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers = []  # remove uvicorn's own plain-text handlers
        uv_logger.propagate = True
