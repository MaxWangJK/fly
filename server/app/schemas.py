from typing import Literal
from uuid import UUID
import json
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', populate_by_name=True)


class DeviceInput(StrictModel):
    device_name: str = Field(alias='deviceName', min_length=1, max_length=120)
    device_type: str = Field(default='desktop', alias='deviceType', max_length=30)
    platform: str = Field(default='windows', max_length=30)
    app_version: str = Field(default='2.0.0', alias='appVersion', max_length=40)


class Credentials(DeviceInput):
    email: EmailStr
    password: str = Field(min_length=10, max_length=1024)

    @field_validator('email', mode='before')
    @classmethod
    def normalize(cls, value):
        return value.strip().lower()


class RefreshInput(StrictModel):
    refresh_token: str = Field(alias='refreshToken', min_length=32, max_length=200)


class Mutation(StrictModel):
    mutation_id: UUID = Field(alias='mutationId')
    entity_type: str = Field(alias='entityType', pattern=r'^[a-z][a-z0-9_]{0,79}$')
    record_id: UUID = Field(alias='recordId')
    base_version: int = Field(alias='baseVersion', ge=0)
    changed_fields: list[str] = Field(alias='changedFields', max_length=200)
    payload: dict = Field(default_factory=dict)
    operation: Literal['upsert', 'delete', 'restore'] = 'upsert'

    @model_validator(mode='after')
    def fields_match(self):
        if len(json.dumps(self.payload, ensure_ascii=False).encode('utf-8')) > 1024 * 1024:
            raise ValueError('Record payload exceeds 1 MiB')
        if len(set(self.changed_fields)) != len(self.changed_fields):
            raise ValueError('Duplicate changedFields')
        if any(not f or len(f) > 120 for f in self.changed_fields):
            raise ValueError('Invalid field name')
        if self.operation != 'delete' and not set(self.changed_fields).issubset(self.payload):
            raise ValueError('changedFields must be present in payload')
        return self


class PushInput(StrictModel):
    mutations: list[Mutation] = Field(min_length=1, max_length=200)


class UploadInput(StrictModel):
    sha256: str = Field(pattern=r'^[a-f0-9]{64}$')
    size: int = Field(ge=0)
