"""Only the backend reads the ignored, runtime-mounted SMTP settings file."""
from email.message import EmailMessage
from email.utils import formataddr
import json
import smtplib
import ssl
from threading import BoundedSemaphore


class VerificationMailer:
    def __init__(self, path):
        self.path = path
        self.slots = BoundedSemaphore(2)

    def send_code(self, recipient, code):
        if not self.slots.acquire(blocking=False):
            raise RuntimeError('Mail service busy')
        try:
            config = json.loads(self.path.read_text(encoding='utf-8'))
            sender = config['sender']
            message = EmailMessage()
            message['From'] = formataddr(('Fly', sender))
            message['To'] = recipient
            message['Subject'] = 'Fly 邮箱验证码 / Email verification code'
            message.set_content(f'Fly 邮箱验证码：{code}\n\n5 分钟内有效。请勿向他人透露。\n'
                f'Your Fly verification code is {code}. It expires in 5 minutes.\n'
                '如果不是你发起的操作，请忽略此邮件。 / If you did not request it, ignore this email.')
            with smtplib.SMTP_SSL(config['server'], int(config.get('port', 465)),
                                  timeout=10, context=ssl.create_default_context()) as smtp:
                smtp.login(sender, config['authCode'])
                smtp.send_message(message)
        finally:
            self.slots.release()
