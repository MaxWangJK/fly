from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def now():
    return datetime.now(timezone.utc)


def uid():
    return str(uuid4())


class Base(DeclarativeBase):
    pass


json_type = JSON().with_variant(JSONB(), 'postgresql')


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    password_hash: Mapped[str] = mapped_column(String(512))
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

# Frozen migration 0001 schema. Do not edit for later migrations.
metadata = Base.metadata
