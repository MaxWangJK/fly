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


class DeviceEnrollmentInput(DeviceInput):
    code: str = Field(min_length=32, max_length=100)


class CaptchaInput(StrictModel):
    email: EmailStr
    purpose: Literal['register', 'bind'] = 'register'

    @field_validator('email', mode='before')
    @classmethod
    def normalize(cls, value):
        return value.strip().lower()


class SendCodeInput(StrictModel):
    challenge_id: UUID = Field(alias='challengeId')
    captcha: str = Field(min_length=4, max_length=4, pattern=r'^[A-Za-z0-9]{4}$')


class VerifyEmailInput(StrictModel):
    challenge_id: UUID = Field(alias='challengeId')
    code: str = Field(pattern=r'^[0-9]{6}$')


class RegisterCredentials(Credentials):
    password: str = Field(min_length=10, max_length=128)
    confirm_password: str = Field(alias='confirmPassword', min_length=10, max_length=128)
    verification_ticket: str = Field(alias='verificationTicket', min_length=32, max_length=100)

    @model_validator(mode='after')
    def same_password(self):
        if self.password != self.confirm_password:
            raise ValueError('Passwords do not match')
        return self


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
    field_clocks: dict[str, tuple[int, str]] = Field(default_factory=dict, alias='fieldClocks', max_length=200)

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
