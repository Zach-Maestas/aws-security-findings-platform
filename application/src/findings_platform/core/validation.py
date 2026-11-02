from typing import Any

_SAFE_KEYS = ("loc", "msg", "type")


def safe_field_errors(errors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep only loc/msg/type from Pydantic error dicts.

    The submitted value ("input") is dropped so it's never echoed back to the client.
    """
    return [{key: err[key] for key in _SAFE_KEYS} for err in errors]
