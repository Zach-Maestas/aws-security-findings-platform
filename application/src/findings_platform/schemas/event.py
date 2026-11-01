from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class UserIdentity(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    identity_type: str = Field(alias="type")
    arn: str | None = None
    invoked_by: str | None = None
    account_id: str | None = None


class CloudTrailEvent(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    event_id: str = Field(alias="eventID")
    event_time: datetime
    event_name: str
    event_source: str
    aws_region: str
    source_ip_address: str = Field(alias="sourceIPAddress")
    recipient_account_id: str
    error_code: str | None = None
    user_identity: UserIdentity
    request_parameters: dict[str, Any] | None = None
