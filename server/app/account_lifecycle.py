"""Account removal and retryable storage cleanup, scoped to one cloud user."""
from sqlalchemy import delete, or_, select, update

from .models import (AccountDeletionCleanup, Device, DeviceEnrollmentCode,
    EmailAuthChallenge, FileBlob, FileUploadSession, ProcessedMutation,
    RefreshToken, SyncChange, SyncConflict, SyncRecord, User, now)


def invalidate_sessions(db, user):
    devices = select(Device.id).where(Device.user_id == user.id)
    db.execute(update(RefreshToken).where(RefreshToken.device_id.in_(devices)).values(revoked_at=now()))
    db.execute(update(Device).where(Device.user_id == user.id).values(revoked_at=now()))
    db.execute(delete(DeviceEnrollmentCode).where(DeviceEnrollmentCode.user_id == user.id))
    db.execute(delete(EmailAuthChallenge).where(or_(
        EmailAuthChallenge.user_id == user.id, EmailAuthChallenge.email == user.email)))


def erase_account(db, user):
    # Caller holds the workspace lock. Explicit order works with FK enforcement
    # in both PostgreSQL and SQLite; no cascade assumptions or shared blob deletion.
    devices = select(Device.id).where(Device.user_id == user.id)
    db.execute(delete(RefreshToken).where(RefreshToken.device_id.in_(devices)))
    for model in (DeviceEnrollmentCode, EmailAuthChallenge, SyncConflict, SyncChange,
                  ProcessedMutation, SyncRecord, FileUploadSession, FileBlob):
        predicate = model.user_id == user.id
        if model is EmailAuthChallenge:
            predicate = or_(predicate, model.email == user.email)
        db.execute(delete(model).where(predicate))
    db.execute(delete(Device).where(Device.user_id == user.id))
    db.add(AccountDeletionCleanup(user_id=user.id))
    db.delete(user)
    db.commit()


def cleanup_deleted_accounts(sessions, storage, user_id=None):
    """Keep failed jobs for the next minute/startup; never resurrect a user."""
    with sessions() as db:
        query = select(AccountDeletionCleanup).order_by(AccountDeletionCleanup.created_at).limit(20).with_for_update(skip_locked=True)
        if user_id is not None:
            query = query.where(AccountDeletionCleanup.user_id == user_id)
        for job in db.scalars(query).all():
            try:
                storage.delete_user(job.user_id)
            except (OSError, ValueError):
                continue
            db.delete(job)
        db.commit()
        if user_id is not None:
            return db.get(AccountDeletionCleanup, user_id) is not None
