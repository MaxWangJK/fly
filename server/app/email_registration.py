import base64
from datetime import timedelta, timezone
import hashlib
import hmac
from io import BytesIO
import secrets

from fastapi import HTTPException
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError

from .models import AuthRateBucket, EmailAuthChallenge, now, uid


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def captcha_image(answer):
    image = Image.new('RGB', (200, 72), '#f2f6ef')
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=38)
    for _ in range(70):
        x, y = secrets.randbelow(200), secrets.randbelow(72)
        draw.ellipse((x, y, x + 2, y + 2), fill='#a9b8a5')
    for i, character in enumerate(answer):
        glyph = Image.new('RGBA', (46, 64), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text((7, 5), character, font=font, fill='#234b39')
        glyph = glyph.rotate(secrets.randbelow(31) - 15, resample=Image.Resampling.BICUBIC)
        image.paste(glyph, (9 + i * 46, secrets.randbelow(6)), glyph)
    for _ in range(3):
        draw.line([(0, secrets.randbelow(72)), (200, secrets.randbelow(72))], fill='#739080', width=1)
    output = BytesIO()
    image.save(output, format='PNG')
    return base64.b64encode(output.getvalue()).decode()


class EmailRegistration:
    def __init__(self, secret, mailer):
        self.secret, self.mailer = secret.encode(), mailer

    def digest(self, kind, identifier, value):
        return hmac.new(self.secret, f'{kind}:{identifier}:{value}'.encode(), hashlib.sha256).hexdigest()

    def limit(self, db, key, maximum, seconds):
        """Atomic database counters survive restarts and apply across workers."""
        key = self.digest('rate', '', key)
        timestamp = now()
        try:
            with db.begin_nested():
                db.add(AuthRateBucket(key=key, window_start=timestamp, count=0))
                db.flush()
        except IntegrityError:
            pass
        db.execute(update(AuthRateBucket).where(AuthRateBucket.key == key,
            AuthRateBucket.window_start <= timestamp - timedelta(seconds=seconds))
            .values(window_start=timestamp, count=0))
        changed = db.execute(update(AuthRateBucket).where(AuthRateBucket.key == key,
            AuthRateBucket.count < maximum).values(count=AuthRateBucket.count + 1))
        db.commit()
        if changed.rowcount != 1:
            raise HTTPException(429, 'Too many attempts; try again later', headers={'Retry-After': str(seconds)})

    def create(self, db, email, purpose, user_id=None):
        self.limit(db, f'captcha:{email}', 20, 3600)
        db.execute(delete(EmailAuthChallenge).where(
            EmailAuthChallenge.captcha_expires_at < now() - timedelta(days=1)))
        db.execute(delete(AuthRateBucket).where(AuthRateBucket.window_start < now() - timedelta(days=1)))
        answer = ''.join(secrets.choice('23456789ABCDEFGHJKLMNPQRSTUVWXYZ') for _ in range(4))
        identifier = uid()
        challenge = EmailAuthChallenge(id=identifier, email=email, purpose=purpose, user_id=user_id,
            captcha_hash=self.digest('captcha', identifier, answer),
            captcha_expires_at=now() + timedelta(minutes=5))
        image = captcha_image(answer)
        db.add(challenge)
        db.commit()
        return {'challengeId': identifier, 'imageBase64': image, 'expiresIn': 300}

    def send(self, db, identifier, answer):
        challenge = db.scalar(select(EmailAuthChallenge).where(EmailAuthChallenge.id == identifier).with_for_update())
        if not challenge or challenge.captcha_used_at or aware(challenge.captcha_expires_at) <= now() or challenge.captcha_attempts >= 5:
            raise HTTPException(400, 'Refresh the graphical verification')
        challenge.captcha_attempts += 1
        valid = hmac.compare_digest(challenge.captcha_hash, self.digest('captcha', identifier, answer.upper()))
        db.commit()
        if not valid:
            raise HTTPException(400, 'Graphical verification is incorrect')
        self.limit(db, f'send-cooldown:{challenge.email}', 1, 60)
        self.limit(db, f'send-hour:{challenge.email}', 5, 3600)
        challenge = db.scalar(select(EmailAuthChallenge).where(EmailAuthChallenge.id == identifier).with_for_update().execution_options(populate_existing=True))
        if challenge.captcha_used_at or aware(challenge.captcha_expires_at) <= now():
            raise HTTPException(400, 'Refresh the graphical verification')
        db.execute(update(EmailAuthChallenge).where(EmailAuthChallenge.email == challenge.email,
            EmailAuthChallenge.purpose == challenge.purpose,
            EmailAuthChallenge.user_id == challenge.user_id,
            EmailAuthChallenge.id != identifier, EmailAuthChallenge.consumed_at.is_(None))
            .values(code_hash=None, ticket_hash=None))
        code = f'{secrets.randbelow(1000000):06d}'
        challenge.captcha_used_at = now()
        challenge.code_hash = self.digest('email-code', identifier, code)
        challenge.code_expires_at = now() + timedelta(minutes=5)
        db.commit()
        try:
            self.mailer.send_code(challenge.email, code, purpose=challenge.purpose)
        except Exception:
            challenge.code_hash = None
            db.commit()
            raise HTTPException(503, 'Verification email could not be sent; retry later') from None
        challenge.sent_at = now()
        db.commit()
        return {'challengeId': identifier, 'expiresIn': 300, 'retryAfter': 60}

    def verify(self, db, identifier, code):
        challenge = db.get(EmailAuthChallenge, identifier)
        if not challenge:
            raise HTTPException(400, 'Invalid or expired email code')
        self.limit(db, f'verify:{challenge.email}', 15, 3600)
        challenge = db.scalar(select(EmailAuthChallenge).where(EmailAuthChallenge.id == identifier).with_for_update().execution_options(populate_existing=True))
        if not challenge.code_hash or not challenge.sent_at or challenge.verified_at or challenge.code_attempts >= 5 or aware(challenge.code_expires_at) <= now():
            raise HTTPException(400, 'Invalid or expired email code')
        challenge.code_attempts += 1
        valid = hmac.compare_digest(challenge.code_hash, self.digest('email-code', identifier, code))
        if not valid:
            db.commit()
            raise HTTPException(400, 'Invalid or expired email code')
        ticket = secrets.token_urlsafe(32)
        challenge.code_hash = None
        challenge.verified_at = now()
        challenge.ticket_hash = self.digest('ticket', '', ticket)
        challenge.ticket_expires_at = now() + timedelta(minutes=10)
        db.commit()
        return {'verificationTicket': ticket, 'expiresIn': 600}

    def proof(self, db, body, purpose, user_id=None):
        challenge = db.scalar(select(EmailAuthChallenge).where(
            EmailAuthChallenge.ticket_hash == self.digest('ticket', '', body.verification_ticket)).with_for_update())
        if not challenge or challenge.consumed_at or not challenge.verified_at or aware(challenge.ticket_expires_at) <= now() or challenge.email != str(body.email) or challenge.purpose != purpose or challenge.user_id != user_id:
            raise HTTPException(400, 'Email verification expired; verify again')
        challenge.consumed_at = now()
        return challenge
