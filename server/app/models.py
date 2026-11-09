from datetime import date, datetime, timezone
from uuid import uuid4
from sqlalchemy import BigInteger, Date, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def now():
    return datetime.now(timezone.utc)


def uid():
    return str(uuid4())


class Base(DeclarativeBase):
    pass


class AnalyticsDevice(Base):
    """An anonymous installation, deliberately unrelated to users/devices."""
    __tablename__ = 'analytics_devices'
    device_code: Mapped[str] = mapped_column(String(32), primary_key=True)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class AnalyticsDailyActive(Base):
    __tablename__ = 'analytics_daily_active'
    id: Mapped[int] = mapped_column(BigInteger().with_variant(Integer, 'sqlite'), primary_key=True, autoincrement=True)
    device_code: Mapped[str] = mapped_column(ForeignKey('analytics_devices.device_code'), index=True)
    active_date: Mapped[date] = mapped_column(Date, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint('device_code', 'active_date', name='uq_analytics_daily_device_date'),)


json_type = JSON().with_variant(JSONB(), 'postgresql')


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    password_hash: Mapped[str] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class EmailAuthChallenge(Base):
    __tablename__ = 'email_auth_challenges'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    email: Mapped[str] = mapped_column(String(320), index=True)
    purpose: Mapped[str] = mapped_column(String(20))
    user_id: Mapped[str | None] = mapped_column(ForeignKey('users.id'))
    captcha_hash: Mapped[str] = mapped_column(String(64))
    captcha_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    captcha_attempts: Mapped[int] = mapped_column(Integer, default=0)
    captcha_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    code_hash: Mapped[str | None] = mapped_column(String(64))
    code_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    code_attempts: Mapped[int] = mapped_column(Integer, default=0)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ticket_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    ticket_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuthRateBucket(Base):
    __tablename__ = 'auth_rate_buckets'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    count: Mapped[int] = mapped_column(Integer, default=0)


class AccountDeletionCleanup(Base):
    """No foreign key: cleanup must survive deletion of the account itself."""
    __tablename__ = 'account_deletion_cleanup'
    user_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Device(Base):
    __tablename__ = 'devices'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    device_name: Mapped[str] = mapped_column(String(120))
    device_type: Mapped[str] = mapped_column(String(30))
    platform: Mapped[str] = mapped_column(String(30))
    app_version: Mapped[str] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RefreshToken(Base):
    __tablename__ = 'refresh_tokens'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_id: Mapped[str] = mapped_column(ForeignKey('devices.id'), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class DeviceEnrollmentCode(Base):
    __tablename__ = 'device_enrollment_codes'
    code_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SyncRecord(Base):
    __tablename__ = 'sync_records'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    entity_type: Mapped[str] = mapped_column(String(80), primary_key=True)
    record_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[int] = mapped_column(Integer)
    data: Mapped[dict] = mapped_column(json_type)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    last_device_id: Mapped[str] = mapped_column(ForeignKey('devices.id'))
    field_clocks: Mapped[dict] = mapped_column(json_type, default=dict, server_default='{}')


class SyncChange(Base):
    __tablename__ = 'sync_changes'
    seq: Mapped[int] = mapped_column(BigInteger().with_variant(Integer, 'sqlite'), primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    entity_type: Mapped[str] = mapped_column(String(80))
    record_id: Mapped[str] = mapped_column(String(36))
    version: Mapped[int] = mapped_column(Integer)
    operation: Mapped[str] = mapped_column(String(20))
    changed_fields: Mapped[list] = mapped_column(json_type)
    data: Mapped[dict] = mapped_column(json_type)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    device_id: Mapped[str] = mapped_column(ForeignKey('devices.id'))
    field_clocks: Mapped[dict] = mapped_column(json_type, default=dict, server_default='{}')


class ProcessedMutation(Base):
    __tablename__ = 'processed_mutations'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    mutation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    request_hash: Mapped[str] = mapped_column(String(64))
    result: Mapped[dict] = mapped_column(json_type)


class SyncConflict(Base):
    __tablename__ = 'sync_conflicts'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    entity_type: Mapped[str] = mapped_column(String(80))
    record_id: Mapped[str] = mapped_column(String(36))
    fields: Mapped[list] = mapped_column(json_type)
    local_candidate: Mapped[dict] = mapped_column(json_type)
    server_candidate: Mapped[dict] = mapped_column(json_type)
    kind: Mapped[str] = mapped_column(String(30))
    device_id: Mapped[str] = mapped_column(ForeignKey('devices.id'))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class FileBlob(Base):
    __tablename__ = 'file_blobs'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    sha256: Mapped[str] = mapped_column(String(64), primary_key=True)
    size: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class FileUploadSession(Base):
    __tablename__ = 'file_upload_sessions'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    sha256: Mapped[str] = mapped_column(String(64))
    size: Mapped[int] = mapped_column(BigInteger)
    offset: Mapped[int] = mapped_column(BigInteger, default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint('user_id', 'id'),)
