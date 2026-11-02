import pytest
from pydantic import ValidationError

from findings_platform.core.validation import safe_field_errors
from findings_platform.schemas.event import CloudTrailEvent


def test_strips_input_from_real_pydantic_errors():
    with pytest.raises(ValidationError) as exc_info:
        CloudTrailEvent.model_validate({"eventTime": "not-a-date"})

    result = safe_field_errors(exc_info.value.errors())

    assert result
    assert all(set(err) == {"loc", "msg", "type"} for err in result)
