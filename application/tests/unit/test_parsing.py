import json

import pytest

from findings_platform.core.exceptions import InvalidEventError
from findings_platform.services.parsing import parse_event


def test_every_fixture_parses(cloudtrail_path):
    event = parse_event(json.loads(cloudtrail_path.read_text()))

    assert event.event_id


def test_missing_event_id_raises_invalid_event(load_cloudtrail):
    raw = load_cloudtrail("sg_open_world_ipv4_ssh")
    del raw["eventID"]

    with pytest.raises(InvalidEventError) as exc_info:
        parse_event(raw)

    fields = exc_info.value.details["fields"]
    assert [f["loc"] for f in fields] == [("eventID",)]


def test_bad_event_time_raises_invalid_event(load_cloudtrail):
    raw = load_cloudtrail("sg_open_world_ipv4_ssh")
    raw["eventTime"] = "not-a-date"

    with pytest.raises(InvalidEventError) as exc_info:
        parse_event(raw)

    assert exc_info.value.status_code == 422
    assert exc_info.value.code == "invalid_event"

    fields = exc_info.value.details["fields"]
    # Pydantic errors also carry "input", "ctx", and "url"; those must be
    # stripped so raw event values never leak into the error response.
    assert all(set(f) == {"loc", "msg", "type"} for f in fields)
