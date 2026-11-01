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

    def send_code(self, recipient, code, purpose='register'):
        action = {'register': '注册账号 / Create account', 'bind': '绑定邮箱 / Link email',
                  'reset': '重置密码 / Reset password', 'delete': '注销账号 / Delete account'}[purpose]
        self._send(recipient, 'Fly 邮箱验证码 / Email verification code',
            f'操作 / Action: {action}\n\nFly 邮箱验证码：{code}\n\n5 分钟内有效。请勿向他人透露。\n'
            f'Your Fly verification code is {code}. It expires in 5 minutes.\n'
            '如果不是你发起的操作，请忽略此邮件。 / If you did not request it, ignore this email.')

    def send_password_changed(self, recipient):
        self._send(recipient, 'Fly 密码已重置 / Password reset completed',
            '你的 Fly 云同步密码已重置，所有设备均需重新登录。\n'
            'Your Fly cloud password was reset. All devices must sign in again.\n'
            '如果不是你发起的，请立即使用邮箱找回密码并检查邮箱安全。\n'
            'If this was not you, recover your password and secure your email account immediately.')

    def _send(self, recipient, subject, content):
        if not self.slots.acquire(blocking=False):
            raise RuntimeError('Mail service busy')
        try:
            config = json.loads(self.path.read_text(encoding='utf-8'))
            sender = config['sender']
            message = EmailMessage()
            message['From'] = formataddr(('Fly', sender))
            message['To'] = recipient
            message['Subject'] = subject
            message.set_content(content)
            with smtplib.SMTP_SSL(config['server'], int(config.get('port', 465)),
                                  timeout=10, context=ssl.create_default_context()) as smtp:
                smtp.login(sender, config['authCode'])
                smtp.send_message(message)
        finally:
            self.slots.release()
