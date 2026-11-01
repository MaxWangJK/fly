import json
import ssl
from app.verification_mail import VerificationMailer


def test_smtp_ssl_sends_six_digit_code_and_keeps_credentials_out_of_content(tmp_path, monkeypatch):
    config = tmp_path / 'smtp.json'
    config.write_text(json.dumps({'server': 'smtp.example.com', 'port': 465,
        'sender': 'verification@example.com', 'authCode': 'TEST_ONLY_AUTH_CODE'}))
    captured = {}

    class FakeSMTP:
        def __init__(self, host, port, **options):
            captured.update(host=host, port=port, options=options)
        def __enter__(self):
            return self
        def __exit__(self, *args):
            captured['quit'] = True
        def login(self, username, password):
            captured['login'] = (username, password)
        def send_message(self, message):
            captured['message'] = message

    monkeypatch.setattr('app.verification_mail.smtplib.SMTP_SSL', FakeSMTP)
    VerificationMailer(config).send_code('recipient@example.com', '012345')
    assert captured['port'] == 465 and captured['options']['timeout'] == 10
    assert isinstance(captured['options']['context'], ssl.SSLContext)
    assert captured['login'] == ('verification@example.com', 'TEST_ONLY_AUTH_CODE')
    message = captured['message']
    assert message['To'] == 'recipient@example.com'
    content = message.get_content()
    assert '012345' in content and 'https://' not in content
    assert 'TEST_ONLY_AUTH_CODE' not in content and captured['quit']
