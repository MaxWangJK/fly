"""Test-only mailbox and direct control of isolated captcha rows; no real email."""
from sqlalchemy.orm import Session
from app.models import EmailAuthChallenge


class RecordingMailer:
    def __init__(self):
        self.messages = []
        self.fail = False
        self.notices = []

    def send_code(self, recipient, code, purpose='register'):
        if self.fail:
            raise RuntimeError('isolated SMTP failure')
        self.messages.append((recipient, code))

    def send_password_changed(self, recipient):
        self.notices.append(recipient)


def challenge(client, email='max@example.com', purpose='register', headers=None):
    response = client.post('/api/auth/registration/captcha', json={'email': email, 'purpose': purpose}, headers=headers)
    assert response.status_code == 200, response.text
    result = response.json()
    service = client.app.state.email_registration
    with Session(client.app.state.engine) as db:
        row = db.get(EmailAuthChallenge, result['challengeId'])
        row.captcha_hash = service.digest('captcha', row.id, 'ABCD')
        db.commit()
    return result['challengeId']


def verification_ticket(client, email='max@example.com', purpose='register', headers=None):
    service = client.app.state.email_registration
    if not isinstance(service.mailer, RecordingMailer):
        service.mailer = RecordingMailer()
    identifier = challenge(client, email, purpose, headers)
    response = client.post('/api/auth/registration/send-code', json={'challengeId': identifier, 'captcha': 'ABCD'})
    assert response.status_code == 200, response.text
    code = service.mailer.messages[-1][1]
    response = client.post('/api/auth/registration/verify-code', json={'challengeId': identifier, 'code': code})
    assert response.status_code == 200, response.text
    return response.json()['verificationTicket']
