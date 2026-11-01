import base64
from datetime import timedelta
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image
import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.enrollment import create_sync_user, issue_device_code
from app.main import create_app
from app.models import AuthRateBucket, Base, EmailAuthChallenge, User, now
from tests.email_auth_helpers import RecordingMailer, challenge, verification_ticket
from tests.test_sync import credentials, headers, mutation, push, register


@pytest.fixture
def api(tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='development-email-auth-test-secret-32', app_env='test',
                        database_url='sqlite://', storage_root=tmp_path)
    with TestClient(create_app(settings, engine, RecordingMailer())) as client:
        yield client
    engine.dispose()


def body(ticket, email='max@example.com'):
    value = credentials(email)
    return {**value, 'verificationTicket': ticket, 'confirmPassword': value['password']}


def expire_limits(api):
    with Session(api.app.state.engine) as db:
        for row in db.scalars(select(AuthRateBucket)):
            row.window_start = now() - timedelta(days=2)
        db.commit()


def test_registration_login_and_three_devices_preserve_user_and_disable_files(api):
    session = register(api, ' Max@Example.com ')
    assert session['email'] == 'max@example.com' and session['emailVerified'] is True
    for _ in range(2):
        login = api.post('/api/auth/login', json=credentials('MAX@example.com'))
        assert login.status_code == 200
        assert login.json()['userId'] == session['userId']
        assert login.json()['deviceId'] != session['deviceId']
    push(api, session, mutation(payload={'name': 'Retained cloud customer'}))
    assert api.get('/api/sync/pull', headers=headers(login.json())).json()['changes'][0]['data']['name'] == 'Retained cloud customer'
    assert api.post('/api/files/upload/init', headers=headers(session), json={'sha256': 'a'*64, 'size': 1}).status_code == 403


def test_graphical_image_is_png_and_wrong_replayed_expired_checks_fail(api):
    result = api.post('/api/auth/registration/captcha', json={'email': 'picture@example.com'})
    image = Image.open(BytesIO(base64.b64decode(result.json()['imageBase64'])))
    assert image.format == 'PNG' and image.size == (200, 72)
    assert 'answer' not in result.json()
    identifier = challenge(api)
    for _ in range(5):
        assert api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'WRNG'}).status_code == 400
    assert api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'}).status_code == 400
    identifier = challenge(api, 'expire@example.com')
    with Session(api.app.state.engine) as db:
        db.get(EmailAuthChallenge, identifier).captcha_expires_at = now() - timedelta(seconds=1)
        db.commit()
    assert api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'}).status_code == 400


def test_code_and_proof_single_use_bound_to_email_and_confirmed_password(api):
    ticket = verification_ticket(api)
    challenge_row = None
    with Session(api.app.state.engine) as db:
        challenge_row = db.scalar(select(EmailAuthChallenge))
        identifier = challenge_row.id
        assert challenge_row.code_hash is None
        assert challenge_row.ticket_hash != ticket
    actual_code = api.app.state.email_registration.mailer.messages[-1][1]
    assert len(actual_code) == 6 and actual_code.isdigit()
    assert api.post('/api/auth/registration/verify-code', json={'challengeId': identifier, 'code': actual_code}).status_code == 400
    assert api.post('/api/auth/register', json=body(ticket, 'another@example.com')).status_code == 400
    mismatch = body(ticket); mismatch['confirmPassword'] = 'different-secret-password'
    invalid = api.post('/api/auth/register', json=mismatch)
    assert invalid.status_code == 422 and 'different-secret-password' not in invalid.text
    assert api.post('/api/auth/register', json=body(ticket)).status_code == 201
    assert api.post('/api/auth/register', json=body(ticket)).status_code == 400
    assert api.post('/api/auth/register', json=credentials()).status_code == 422


def test_resend_cooldown_old_code_invalidation_and_persistent_attempt_budget(api):
    first = challenge(api)
    assert api.post('/api/auth/registration/send-code', json={'challengeId': first, 'captcha': 'ABCD'}).status_code == 200
    old_code = api.app.state.email_registration.mailer.messages[-1][1]
    second = challenge(api)
    assert api.post('/api/auth/registration/send-code', json={'challengeId': second, 'captcha': 'ABCD'}).status_code == 429
    expire_limits(api)
    assert api.post('/api/auth/registration/send-code', json={'challengeId': second, 'captcha': 'ABCD'}).status_code == 200
    assert api.post('/api/auth/registration/verify-code', json={'challengeId': first, 'code': old_code}).status_code == 400
    right = api.app.state.email_registration.mailer.messages[-1][1]
    wrong = '000000' if right != '000000' else '111111'
    for _ in range(5):
        assert api.post('/api/auth/registration/verify-code', json={'challengeId': second, 'code': wrong}).status_code == 400
    assert api.post('/api/auth/registration/verify-code', json={'challengeId': second, 'code': right}).status_code == 400


def test_expired_code_and_expired_ticket_rejected(api):
    identifier = challenge(api)
    api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'})
    with Session(api.app.state.engine) as db:
        db.get(EmailAuthChallenge, identifier).code_expires_at = now() - timedelta(seconds=1)
        db.commit()
    code = api.app.state.email_registration.mailer.messages[-1][1]
    assert api.post('/api/auth/registration/verify-code', json={'challengeId': identifier, 'code': code}).status_code == 400
    ticket = verification_ticket(api, 'new@example.com')
    with Session(api.app.state.engine) as db:
        row = db.scalar(select(EmailAuthChallenge).where(EmailAuthChallenge.email == 'new@example.com'))
        row.ticket_expires_at = now() - timedelta(seconds=1)
        db.commit()
    assert api.post('/api/auth/register', json=body(ticket, 'new@example.com')).status_code == 400


def test_smtp_failure_is_actionable_and_never_confirms_delivery(api):
    api.app.state.email_registration.mailer.fail = True
    identifier = challenge(api)
    result = api.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'})
    assert result.status_code == 503 and 'SMTP failure' not in result.text
    with Session(api.app.state.engine) as db:
        row = db.get(EmailAuthChallenge, identifier)
        assert row.code_hash is None and row.sent_at is None
    assert result.headers['cache-control'] == 'no-store'


def test_bind_temporary_space_keeps_existing_data_and_other_devices(api):
    with Session(api.app.state.engine) as db:
        user = create_sync_user(db)
        first_code = issue_device_code(db, user.id)
        second_code = issue_device_code(db, user.id)
        db.commit()
    one = api.post('/api/sync/enroll-device', json={'code': first_code, 'deviceName': 'Existing PC'}).json()
    two = api.post('/api/sync/enroll-device', json={'code': second_code, 'deviceName': 'Existing phone'}).json()
    push(api, one, mutation(payload={'name': 'Before email was linked'}))
    ticket = verification_ticket(api, 'linked@example.com', 'bind', headers(one))
    assert api.post('/api/auth/register', json=body(ticket, 'linked@example.com')).status_code == 400
    linked = api.post('/api/auth/link-email', json=body(ticket, 'linked@example.com'), headers=headers(one))
    assert linked.status_code == 200 and linked.json()['userId'] == one['userId']
    assert linked.json()['emailVerified'] is True
    assert api.get('/api/sync/pull', headers=headers(two)).json()['changes'][0]['data']['name'] == 'Before email was linked'
    login = api.post('/api/auth/login', json=credentials('linked@example.com'))
    assert login.status_code == 200 and login.json()['userId'] == one['userId']


def test_duplicate_email_and_disabled_feature_cannot_bypass_verification(api):
    register(api)
    expire_limits(api)
    ticket = verification_ticket(api)
    assert api.post('/api/auth/register', json=body(ticket)).status_code == 409
    settings = api.app.state.settings.model_copy(update={'allow_password_auth': False})
    with TestClient(create_app(settings, api.app.state.engine, RecordingMailer())) as disabled:
        assert disabled.post('/api/auth/registration/captcha', json={'email': 'off@example.com'}).status_code == 404
        assert disabled.post('/api/auth/login', json=credentials()).status_code == 404
