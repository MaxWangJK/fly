from datetime import timedelta
import hashlib
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine, event, func, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.account_lifecycle import cleanup_deleted_accounts
from app.config import Settings
from app.enrollment import issue_device_code
from app.main import create_app
from app.models import (AccountDeletionCleanup, AuthRateBucket, Base, Device,
    DeviceEnrollmentCode, EmailAuthChallenge, FileBlob, FileUploadSession,
    ProcessedMutation, RefreshToken, SyncChange, SyncConflict, SyncRecord, User, now)
from tests.email_auth_helpers import RecordingMailer, challenge, verification_ticket
from tests.test_sync import credentials, headers, mutation, push, register


@pytest.fixture
def api(tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    @event.listens_for(engine, 'connect')
    def foreign_keys(connection, _):
        connection.execute('PRAGMA foreign_keys=ON')
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='isolated-lifecycle-test-secret-at-least-32',
        app_env='test', database_url='sqlite://', storage_root=tmp_path)
    with TestClient(create_app(settings, engine, RecordingMailer())) as client:
        yield client
    engine.dispose()


def expire_limits(api):
    with Session(api.app.state.engine) as db:
        for row in db.scalars(select(AuthRateBucket)):
            row.window_start = now() - timedelta(days=2)
        db.commit()


def reset_body(ticket, email='max@example.com'):
    return dict(email=email, password='new-test-password', confirmPassword='new-test-password', verificationTicket=ticket)


def delete_body(ticket, email='max@example.com'):
    return dict(email=email, password=credentials()['password'], verificationTicket=ticket, confirmation='DELETE')


def test_reset_revokes_all_sessions_and_codes_but_preserves_cloud_data(api):
    first = register(api)
    second = api.post('/api/auth/login', json=credentials()).json()
    push(api, first, mutation(payload={'name': 'Retained customer'}))
    with Session(api.app.state.engine) as db:
        enrollment = issue_device_code(db, first['userId'])
        db.commit()
    expire_limits(api)
    ticket = verification_ticket(api, purpose='reset')
    mismatch = reset_body(ticket); mismatch['confirmPassword'] = 'different-test-password'
    result = api.post('/api/auth/password/reset', json=mismatch)
    assert result.status_code == 422 and 'different-test-password' not in result.text
    result = api.post('/api/auth/password/reset', json=reset_body(ticket))
    assert result.status_code == 200, result.text
    assert result.json()['signInRequired']
    assert api.app.state.email_registration.mailer.notices == ['max@example.com']
    for old in (first, second):
        assert api.get('/api/account/me', headers=headers(old)).status_code == 401
        assert api.post('/api/auth/refresh', json={'refreshToken': old['refreshToken']}).status_code == 401
    assert api.post('/api/auth/password/reset', json=reset_body(ticket)).status_code == 400
    assert api.post('/api/auth/login', json=credentials()).status_code == 401
    login = api.post('/api/auth/login', json={**credentials(), 'password': 'new-test-password'})
    assert login.status_code == 200 and login.json()['userId'] == first['userId']
    changes = api.get('/api/sync/pull', headers=headers(login.json())).json()['changes']
    assert changes[0]['data']['name'] == 'Retained customer'
    with Session(api.app.state.engine) as db:
        assert db.get(DeviceEnrollmentCode, hashlib.sha256(enrollment.encode()).hexdigest()) is None
        assert db.scalar(select(func.count()).select_from(EmailAuthChallenge)) == 0


def test_reset_request_does_not_disclose_account_existence_and_proof_has_one_purpose(api):
    register(api)
    expire_limits(api)
    for email in ('max@example.com', 'unknown@example.com'):
        identifier = challenge(api, email, 'reset')
        response = api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'})
        assert response.status_code == 200
        assert set(response.json()) == {'challengeId', 'expiresIn', 'retryAfter'}
    other_ticket = verification_ticket(api, 'new@example.com')
    assert api.post('/api/auth/password/reset', json=reset_body(other_ticket, 'new@example.com')).status_code == 400
    expire_limits(api)
    ticket = verification_ticket(api, 'unknown@example.com', 'reset')
    assert api.post('/api/auth/password/reset', json=reset_body(ticket, 'unknown@example.com')).status_code == 400
    with Session(api.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(User)) == 1


def test_delete_requires_own_email_authenticated_proof_password_and_confirmation(api):
    owner = register(api)
    expire_limits(api)
    assert api.post('/api/auth/registration/captcha', json={'email': 'max@example.com', 'purpose': 'delete'}).status_code == 401
    assert api.post('/api/auth/registration/captcha', headers=headers(owner), json={'email': 'other@example.com', 'purpose': 'delete'}).status_code == 400
    reset = verification_ticket(api, purpose='reset')
    assert api.post('/api/account/delete', headers=headers(owner), json=delete_body(reset)).status_code == 400
    expire_limits(api)
    ticket = verification_ticket(api, purpose='delete', headers=headers(owner))
    body = delete_body(ticket); body['confirmation'] = 'yes'
    assert api.post('/api/account/delete', headers=headers(owner), json=body).status_code == 422
    body = delete_body(ticket); body['password'] = 'wrong-test-password'
    result = api.post('/api/account/delete', headers=headers(owner), json=body)
    assert result.status_code == 400 and 'password is incorrect' in result.text
    assert api.get('/api/account/me', headers=headers(owner)).status_code == 200
    assert api.post('/api/account/delete', headers=headers(owner), json=delete_body(ticket)).status_code == 200


def test_delete_erases_only_this_user_including_legacy_files_and_sessions(api):
    owner = register(api)
    other = register(api, 'other@example.com')
    push(api, owner, mutation(payload={'name': 'Erase this'}))
    push(api, other, mutation(payload={'name': 'Keep this'}))
    storage = api.app.state.storage
    for user in (owner, other):
        storage.blob(user['userId'], 'a'*64).write_bytes(b'legacy photo')
        storage.partial(user['userId'], str(uuid4())).write_bytes(b'partial')
        with Session(api.app.state.engine) as db:
            db.add(FileBlob(user_id=user['userId'], sha256='a'*64, size=12))
            db.add(FileUploadSession(user_id=user['userId'], sha256='a'*64, size=12, expires_at=now()+timedelta(hours=1)))
            db.add(SyncConflict(user_id=user['userId'], entity_type='tasks', record_id=str(uuid4()),
                fields=['title'], local_candidate={}, server_candidate={}, kind='edit', device_id=user['deviceId']))
            db.commit()
    expire_limits(api)
    ticket = verification_ticket(api, purpose='delete', headers=headers(owner))
    response = api.post('/api/account/delete', headers=headers(owner), json=delete_body(ticket))
    assert response.status_code == 200, response.text
    assert response.json() == {'ok': True, 'localDataPreserved': True, 'fileCleanupPending': False}
    assert not (storage.root / owner['userId']).exists()
    assert storage.blob(other['userId'], 'a'*64).read_bytes() == b'legacy photo'
    for model in (Device, DeviceEnrollmentCode, EmailAuthChallenge, SyncRecord, SyncChange,
                  SyncConflict, ProcessedMutation, FileBlob, FileUploadSession):
        with Session(api.app.state.engine) as db:
            assert not db.scalars(select(model).where(model.user_id == owner['userId'])).all()
    with Session(api.app.state.engine) as db:
        assert db.get(User, owner['userId']) is None
        assert db.get(User, other['userId']) is not None
        assert not db.scalars(select(RefreshToken).where(RefreshToken.device_id == owner['deviceId'])).all()
    assert api.post('/api/auth/refresh', json={'refreshToken': owner['refreshToken']}).status_code == 401
    assert api.post('/api/sync/push', headers=headers(owner), json={'mutations': []}).status_code == 401
    assert api.get('/api/sync/pull', headers=headers(other)).json()['changes'][0]['data']['name'] == 'Keep this'


def test_failed_file_cleanup_is_durable_and_retried_after_account_is_removed(api, monkeypatch):
    owner = register(api)
    storage = api.app.state.storage
    storage.blob(owner['userId'], 'a'*64).write_bytes(b'to erase')
    expire_limits(api)
    ticket = verification_ticket(api, purpose='delete', headers=headers(owner))
    original = storage.delete_user
    def offline(_):
        raise PermissionError('isolated disk failure')
    monkeypatch.setattr(storage, 'delete_user', offline)
    response = api.post('/api/account/delete', headers=headers(owner), json=delete_body(ticket))
    assert response.status_code == 200 and response.json()['fileCleanupPending'] is True
    with Session(api.app.state.engine) as db:
        assert db.get(User, owner['userId']) is None
        assert db.get(AccountDeletionCleanup, owner['userId']) is not None
    monkeypatch.setattr(storage, 'delete_user', original)
    cleanup_deleted_accounts(sessionmaker(api.app.state.engine), storage)
    assert not (storage.root / owner['userId']).exists()
    with Session(api.app.state.engine) as db:
        assert db.get(AccountDeletionCleanup, owner['userId']) is None


def test_expired_reset_ticket_cannot_change_password(api):
    owner = register(api)
    expire_limits(api)
    ticket = verification_ticket(api, purpose='reset')
    with Session(api.app.state.engine) as db:
        for row in db.scalars(select(EmailAuthChallenge)):
            row.ticket_expires_at = now()-timedelta(seconds=1)
        db.commit()
    assert api.post('/api/auth/password/reset', json=reset_body(ticket)).status_code == 400
    assert api.get('/api/account/me', headers=headers(owner)).status_code == 200
