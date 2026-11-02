import pytest
from pydantic import ValidationError

from findings_platform.core.validation import safe_field_errors
from findings_platform.schemas.event import CloudTrailEvent


def test_strips_input_from_real_pydantic_errors():
    # Use a real ValidationError so we test the keys Pydantic actually emits.
    with pytest.raises(ValidationError) as exc_info:
        CloudTrailEvent.model_validate({"eventTime": "not-a-date"})

    result = safe_field_errors(exc_info.value.errors())

    assert result
    assert all(set(err) == {"loc", "msg", "type"} for err in result)


def test_keeps_only_loc_msg_type():
    errors = [
        {
            "loc": ("eventID",),
            "msg": "Field required",
            "type": "missing",
            "input": {"secret": "value"},
            "ctx": {"x": 1},
            "url": "https://errors.pydantic.dev",
        }
    ]

    assert safe_field_errors(errors) == [
        {"loc": ("eventID",), "msg": "Field required", "type": "missing"}
    ]


def test_empty_errors_returns_empty_list():
    assert safe_field_errors([]) == []
