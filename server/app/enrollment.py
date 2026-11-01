"""Operator-only provisioning. The public API cannot create users or choose a user ID."""
from datetime import timedelta
import hashlib
import secrets
from uuid import uuid4
from .models import DeviceEnrollmentCode, User, now


def create_sync_user(db):
    user_id = str(uuid4())
    user = User(id=user_id, email=f'{user_id}@sync.invalid', password_hash='!device-enrollment-only')
    db.add(user)
    db.flush()
    return user


def issue_device_code(db, user_id, minutes=15):
    if not 1 <= minutes <= 60 or db.get(User, user_id) is None:
        raise ValueError('Existing user and validity from 1 to 60 minutes required')
    code = 'fly-sync-' + secrets.token_urlsafe(32)
    db.add(DeviceEnrollmentCode(code_hash=hashlib.sha256(code.encode()).hexdigest(),
        user_id=user_id, expires_at=now() + timedelta(minutes=minutes)))
    db.flush()
    return code
