import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select

from findings_platform.models.enums import Status, SuppressionReason
from findings_platform.models.event import Event
from findings_platform.models.finding import Finding


def test_risky_event_creates_finding(client, db_session, load_cloudtrail):

    response = client.post(
        "/api/v1/events", json=load_cloudtrail("sg_open_world_ipv4_ssh")
    )

    body = response.json()

    assert response.status_code == 201
    assert body["outcome"] == "created"

    finding_id = body["finding_id"]

    assert db_session.get(Finding, uuid.UUID(finding_id)) is not None


def test_repeat_event_updates_existing_finding(client, load_cloudtrail):
    payload = load_cloudtrail("sg_open_world_ipv4_ssh")

    first = client.post("/api/v1/events", json=payload)
    assert first.status_code == 201
    first_finding_id = first.json()["finding_id"]

    payload["eventID"] = str(uuid.uuid4())
    second = client.post("/api/v1/events", json=payload)
    assert second.status_code == 200

    body = second.json()
    assert body["outcome"] == "updated"
    assert body["finding_id"] == first_finding_id


def test_same_event_twice_is_skipped_as_duplicate(client, db_session, load_cloudtrail):
    payload = load_cloudtrail("sg_open_world_ipv4_ssh")

    first = client.post("/api/v1/events", json=payload)
    second = client.post("/api/v1/events", json=payload)

    assert first.status_code == 201
    assert second.status_code == 200
    body = second.json()
    assert body["outcome"] == "duplicate"
    assert body["finding_id"] is None

    # The duplicate stored nothing: still one finding with one event.
    assert db_session.scalar(select(func.count()).select_from(Finding)) == 1
    assert db_session.scalar(select(func.count()).select_from(Event)) == 1


def test_benign_event_is_ignored_and_stores_nothing(
    client, db_session, load_cloudtrail
):
    response = client.post(
        "/api/v1/events", json=load_cloudtrail("sg_benign_single_ip")
    )

    assert response.status_code == 200
    body = response.json()
    assert body["outcome"] == "ignored"
    assert body["reason"] == "not_risky"
    assert body["finding_id"] is None

    assert db_session.scalar(select(func.count()).select_from(Finding)) == 0
    assert db_session.scalar(select(func.count()).select_from(Event)) == 0


def test_malformed_event_returns_422_without_echoing_input(client, load_cloudtrail):
    payload = load_cloudtrail("sg_open_world_ipv4_ssh")
    payload["eventTime"] = "not-a-timestamp"

    response = client.post("/api/v1/events", json=payload)

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "invalid_event"
    fields = error["details"]["fields"]
    assert any(field["loc"][-1] == "eventTime" for field in fields)
    # Sanitized: the rejected value never comes back in the response.
    assert "not-a-timestamp" not in response.text


def _post_new_occurrence(client, load_cloudtrail):
    """POST the SG fixture under a fresh eventID: same fingerprint, new event."""
    payload = load_cloudtrail("sg_open_world_ipv4_ssh")
    payload["eventID"] = str(uuid.uuid4())
    return client.post("/api/v1/events", json=payload)


def test_event_for_suppressed_finding_attaches_to_it(
    client, db_session, load_cloudtrail
):
    first = _post_new_occurrence(client, load_cloudtrail)
    finding = db_session.get(Finding, uuid.UUID(first.json()["finding_id"]))
    finding.status = Status.SUPPRESSED
    finding.suppression_reason = SuppressionReason.ACCEPTED_RISK
    db_session.commit()

    second = _post_new_occurrence(client, load_cloudtrail)

    assert second.status_code == 200
    body = second.json()
    assert body["outcome"] == "updated"
    assert body["finding_id"] == first.json()["finding_id"]
    db_session.refresh(finding)
    assert finding.status is Status.SUPPRESSED


def test_event_for_resolved_finding_opens_new_finding(
    client, db_session, load_cloudtrail
):
    first = _post_new_occurrence(client, load_cloudtrail)
    old_finding = db_session.get(Finding, uuid.UUID(first.json()["finding_id"]))
    old_finding.status = Status.RESOLVED
    old_finding.resolved_at = datetime.now(UTC)
    db_session.commit()

    second = _post_new_occurrence(client, load_cloudtrail)

    assert second.status_code == 201
    body = second.json()
    assert body["outcome"] == "created"
    assert body["finding_id"] != first.json()["finding_id"]
    # The resolved finding is left as it was; the recurrence is a separate row.
    db_session.refresh(old_finding)
    assert old_finding.status is Status.RESOLVED
    assert db_session.scalar(select(func.count()).select_from(Finding)) == 2
