import asyncio
from collections import defaultdict, deque
from datetime import timedelta, timezone
import hashlib
import secrets
import json
import time
from uuid import UUID
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from fastapi import Depends, FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
import jwt
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from .config import Settings
from .models import Base, Device, FileBlob, FileUploadSession, RefreshToken, SyncChange, SyncConflict, SyncRecord, User, now
from .schemas import Credentials, PushInput, RefreshInput, UploadInput
from .storage import LocalDiskBlobStorage
from .sync import accept, record_json

WS_POLL_SECONDS = 2
WS_HEARTBEAT_SECONDS = 30


class BodyLimit:
    def __init__(self, app, limit):
        self.app, self.limit = app, limit

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        # Buffer bounded API requests before passing them to parsers. File chunks are bounded too.
        body = bytearray()
        while True:
            message = await receive()
            if message['type'] == 'http.disconnect':
                return
            body.extend(message.get('body', b''))
            if len(body) > self.limit:
                await send({'type': 'http.response.start', 'status': 413, 'headers': []})
                await send({'type': 'http.response.body', 'body': b'Payload too large'})
                return
            if not message.get('more_body', False):
                break
        delivered = False

        async def bounded_receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {'type': 'http.request', 'body': bytes(body), 'more_body': False}
            return await receive()

        await self.app(scope, bounded_receive, send)


def aware(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def create_app(settings=None, engine=None):
    settings = settings or Settings()
    engine = engine or create_engine(settings.database_url, pool_pre_ping=True)
    sessions = sessionmaker(engine, expire_on_commit=False)
    storage = LocalDiskBlobStorage(settings.storage_root)
    password_hasher = PasswordHasher()
    dummy_hash = password_hasher.hash(secrets.token_urlsafe(32))
    app = FastAPI(title='Fly Sync', version='2.0.0')
    app.state.engine, app.state.settings = engine, settings
    allowed_hosts = [host.strip() for host in settings.allowed_hosts.split(',') if host.strip()]
    # Host headers retain brackets around IPv6 literals; configuration may omit them.
    allowed_hosts = [f'[{host}]' if ':' in host and not host.startswith('[') else host
                     for host in allowed_hosts]
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts, www_redirect=False)
    app.add_middleware(CORSMiddleware, allow_origins=[o for o in settings.cors_origins.split(',') if o],
                       allow_credentials=False, allow_methods=['GET', 'POST', 'PUT'], allow_headers=['Authorization', 'Content-Type'])
    app.add_middleware(BodyLimit, limit=settings.max_request_bytes)
    attempts = defaultdict(deque)

    def database():
        with sessions() as db:
            yield db

    def rate_limit(request):
        # Deployment uses one API worker; nginx also enforces a shared IP limit.
        key = request.client.host if request.client else 'unknown'
        timestamp = time.monotonic()
        bucket = attempts[key]
        while bucket and bucket[0] < timestamp - 60:
            bucket.popleft()
        if len(bucket) >= 10:
            raise HTTPException(429, 'Try again later', headers={'Retry-After': '60'})
        bucket.append(timestamp)
        if len(attempts) > 10000:
            for k in list(attempts):
                if not attempts[k] or attempts[k][-1] < timestamp - 60:
                    del attempts[k]

    def token_device(token, db):
        try:
            claims = jwt.decode(token, settings.jwt_private_secret, algorithms=['HS256'],
                                audience='fly-client', issuer='fly-sync', options={'require': ['exp', 'iat', 'sub', 'device']})
            device = db.get(Device, str(UUID(claims['device'])))
            if not device or device.revoked_at or device.user_id != claims['sub']:
                raise ValueError()
            return device
        except (jwt.PyJWTError, ValueError, KeyError):
            raise HTTPException(401, 'Invalid session') from None

    def authenticated(request: Request, db: Session = Depends(database)):
        authorization = request.headers.get('authorization', '')
        if not authorization.startswith('Bearer '):
            raise HTTPException(401, 'Authentication required')
        return token_device(authorization[7:], db)

    def lock_user(db, user_id):
        # Serialize ALL writes for a workspace, including the first creation of a record.
        # This also guarantees that user-specific cursor order follows commit order.
        return db.scalar(select(User).where(User.id == user_id).with_for_update())

    def issue(db, device):
        refresh = secrets.token_urlsafe(48)
        db.add(RefreshToken(token_hash=digest(refresh), device_id=device.id,
                            expires_at=now() + timedelta(days=settings.refresh_days)))
        device.last_seen_at = now()
        user = db.get(User, device.user_id)
        access = jwt.encode({'sub': user.id, 'device': device.id, 'iat': now(),
            'exp': now() + timedelta(minutes=settings.access_minutes), 'iss': 'fly-sync', 'aud': 'fly-client'},
            settings.jwt_private_secret, algorithm='HS256')
        return {'accessToken': access, 'refreshToken': refresh, 'userId': user.id,
                'deviceId': device.id, 'email': user.email, 'expiresIn': settings.access_minutes * 60}

    def add_device(db, user, body):
        device = Device(user_id=user.id, device_name=body.device_name,
                        device_type=body.device_type, platform=body.platform, app_version=body.app_version)
        db.add(device)
        db.flush()
        return device

    @app.get('/api/health')
    def health(db: Session = Depends(database)):
        db.execute(select(1))
        return {'status': 'ok', 'apiVersion': 1}

    @app.post('/api/auth/register', status_code=201)
    def register(body: Credentials, request: Request, db: Session = Depends(database)):
        rate_limit(request)
        user = User(email=str(body.email).lower(), password_hash=password_hasher.hash(body.password))
        db.add(user)
        try:
            db.flush()
            result = issue(db, add_device(db, user, body))
            db.commit()
            return result
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'Email already registered') from None

    @app.post('/api/auth/login')
    def login(body: Credentials, request: Request, db: Session = Depends(database)):
        rate_limit(request)
        user = db.scalar(select(User).where(User.email == str(body.email).lower()))
        try:
            password_hasher.verify(user.password_hash if user else dummy_hash, body.password)
        except (VerificationError, InvalidHashError):
            raise HTTPException(401, 'Invalid credentials') from None
        if not user:
            raise HTTPException(401, 'Invalid credentials')
        lock_user(db, user.id)
        result = issue(db, add_device(db, user, body))
        db.commit()
        return result

    @app.post('/api/auth/refresh')
    def refresh(body: RefreshInput, db: Session = Depends(database)):
        token = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == digest(body.refresh_token)).with_for_update())
        if not token or token.revoked_at or aware(token.expires_at) <= now():
            raise HTTPException(401, 'Invalid refresh token')
        device = db.scalar(select(Device).where(Device.id == token.device_id).with_for_update())
        if device.revoked_at:
            raise HTTPException(401, 'Revoked device')
        token.revoked_at = now()
        result = issue(db, device)
        db.commit()
        return result

    @app.post('/api/auth/logout')
    def logout(device=Depends(authenticated), db: Session = Depends(database)):
        device.revoked_at = now()
        db.commit()
        return {'ok': True}

    @app.get('/api/account/me')
    def me(device=Depends(authenticated), db: Session = Depends(database)):
        user = db.get(User, device.user_id)
        blob_count, size = db.execute(select(func.count(), func.coalesce(func.sum(FileBlob.size), 0)).where(FileBlob.user_id == user.id)).one()
        count = db.scalar(select(func.count()).select_from(SyncRecord).where(SyncRecord.user_id == user.id,
            SyncRecord.entity_type == 'attachments', SyncRecord.deleted_at.is_(None)))
        return {'userId': user.id, 'email': user.email, 'fileCount': count, 'blobCount': blob_count, 'fileStorageBytes': size,
                'capabilities': {'deleteAccount': False, 'passwordReset': False}}

    @app.get('/api/devices')
    def devices(device=Depends(authenticated), db: Session = Depends(database)):
        return [{'id': d.id, 'deviceName': d.device_name, 'platform': d.platform,
                 'revoked': d.revoked_at is not None, 'lastSeenAt': d.last_seen_at.isoformat()}
                for d in db.scalars(select(Device).where(Device.user_id == device.user_id))]

    @app.post('/api/devices/{device_id}/revoke')
    def revoke(device_id: UUID, device=Depends(authenticated), db: Session = Depends(database)):
        target = db.get(Device, str(device_id))
        if not target or target.user_id != device.user_id:
            raise HTTPException(404, 'Device not found')
        target.revoked_at = now()
        db.commit()
        return {'ok': True}

    @app.post('/api/sync/push')
    def push(body: PushInput, device=Depends(authenticated), db: Session = Depends(database)):
        lock_user(db, device.user_id)
        results = [accept(db, device, mutation) for mutation in body.mutations]
        device.last_seen_at = now()
        db.commit()
        return {'results': results}

    @app.get('/api/sync/pull')
    def pull(after: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=200),
             device=Depends(authenticated), db: Session = Depends(database)):
        changes = db.scalars(select(SyncChange).where(SyncChange.user_id == device.user_id,
                SyncChange.seq > after).order_by(SyncChange.seq).limit(limit + 1)).all()
        selected = []
        used_bytes = 0
        for change in changes[:limit]:
            encoded_size = len(json.dumps(record_json(change), ensure_ascii=False).encode('utf-8'))
            if selected and used_bytes + encoded_size > 4 * 1024 * 1024:
                break
            selected.append(change)
            used_bytes += encoded_size
        return {'changes': [dict(record_json(c), seq=c.seq, operation=c.operation,
                                  changedFields=c.changed_fields) for c in selected],
                'nextCursor': selected[-1].seq if selected else after, 'hasMore': len(changes) > len(selected)}

    @app.get('/api/sync/bootstrap')
    def bootstrap(after: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=200),
                  device=Depends(authenticated), db: Session = Depends(database)):
        # Durable change-log pagination is also the bootstrap protocol. The client folds
        # pages transactionally; no fragile multi-request live-record snapshot is used.
        return pull(after, limit, device, db)

    @app.get('/api/sync/conflicts')
    def conflicts(after: str = '', limit: int = Query(100, ge=1, le=200),
                  device=Depends(authenticated), db: Session = Depends(database)):
        items = db.scalars(select(SyncConflict).where(SyncConflict.user_id == device.user_id,
            SyncConflict.id > after, SyncConflict.resolved_at.is_(None)).order_by(SyncConflict.id).limit(limit)).all()
        return [{'id': c.id, 'entityType': c.entity_type, 'recordId': c.record_id, 'fields': c.fields,
                 'localCandidate': c.local_candidate, 'serverCandidate': c.server_candidate,
                 'kind': c.kind, 'deviceId': c.device_id, 'createdAt': c.created_at.isoformat()} for c in items]

    @app.post('/api/sync/conflicts/{conflict_id}/resolve')
    def resolve(conflict_id: UUID, device=Depends(authenticated), db: Session = Depends(database)):
        conflict = db.get(SyncConflict, str(conflict_id))
        if not conflict or conflict.user_id != device.user_id:
            raise HTTPException(404, 'Conflict not found')
        conflict.resolved_at = now()
        db.commit()
        return {'ok': True}

    @app.post('/api/files/upload/init')
    def init_upload(body: UploadInput, device=Depends(authenticated), db: Session = Depends(database)):
        if body.size > settings.max_file_bytes:
            raise HTTPException(413, 'File too large')
        blob = db.get(FileBlob, (device.user_id, body.sha256))
        if blob:
            if blob.size != body.size:
                raise HTTPException(409, 'Hash size mismatch')
            return {'exists': True, 'chunkBytes': settings.chunk_bytes}
        upload = db.scalar(select(FileUploadSession).where(FileUploadSession.user_id == device.user_id,
            FileUploadSession.sha256 == body.sha256, FileUploadSession.size == body.size,
            FileUploadSession.expires_at > now(), FileUploadSession.completed_at.is_(None)))
        if upload is None:
            upload = FileUploadSession(user_id=device.user_id, sha256=body.sha256, size=body.size,
                                       expires_at=now() + timedelta(days=7))
            db.add(upload)
        db.commit()
        return {'exists': False, 'uploadId': upload.id, 'offset': upload.offset, 'chunkBytes': settings.chunk_bytes}

    def owned_upload(db, device, upload_id):
        upload = db.scalar(select(FileUploadSession).where(FileUploadSession.id == str(upload_id)).with_for_update())
        if not upload or upload.user_id != device.user_id:
            raise HTTPException(404, 'Upload not found')
        if aware(upload.expires_at) <= now() or upload.completed_at:
            raise HTTPException(409, 'Upload closed')
        return upload

    @app.put('/api/files/upload/{upload_id}/chunk')
    async def chunk(upload_id: UUID, request: Request, offset: int = Query(ge=0),
                    device=Depends(authenticated), db: Session = Depends(database)):
        upload = owned_upload(db, device, upload_id)
        if offset != upload.offset:
            raise HTTPException(409, {'offset': upload.offset})
        content = await request.body()
        if not content or len(content) > settings.chunk_bytes or offset + len(content) > upload.size:
            raise HTTPException(413, 'Invalid chunk size')
        path = storage.partial(device.user_id, upload.id)
        with path.open('r+b' if path.exists() else 'w+b') as output:
            output.seek(0, 2)
            if output.tell() < offset:
                raise HTTPException(409, 'Upload storage incomplete; restart upload')
            output.truncate(offset)
            output.seek(offset)
            output.write(content)
            output.flush()
            import os
            os.fsync(output.fileno())
        upload.offset += len(content)
        db.commit()
        return {'offset': upload.offset}

    @app.post('/api/files/upload/{upload_id}/complete')
    def complete(upload_id: UUID, device=Depends(authenticated), db: Session = Depends(database)):
        lock_user(db, device.user_id)
        saved = db.get(FileUploadSession, str(upload_id))
        if saved and saved.user_id == device.user_id and saved.completed_at:
            return {'sha256': saved.sha256, 'size': saved.size}
        upload = owned_upload(db, device, upload_id)
        if upload.offset != upload.size:
            raise HTTPException(409, 'Upload incomplete')
        path = storage.partial(device.user_id, upload.id)
        if upload.size == 0 and not path.exists():
            path.touch()
        target = storage.blob(device.user_id, upload.sha256)
        source = path if path.exists() else target
        if not source.exists():
            raise HTTPException(409, 'Upload storage incomplete')
        with source.open('rb') as content:
            actual = hashlib.file_digest(content, 'sha256').hexdigest()
        if actual != upload.sha256 or source.stat().st_size != upload.size:
            raise HTTPException(422, 'Checksum mismatch')
        if source != target:
            source.replace(target)
        if not db.get(FileBlob, (device.user_id, upload.sha256)):
            db.add(FileBlob(user_id=device.user_id, sha256=upload.sha256, size=upload.size))
        upload.completed_at = now()
        db.commit()
        return {'sha256': upload.sha256, 'size': upload.size}

    @app.get('/api/files/{file_id}/download')
    def download(file_id: UUID, device=Depends(authenticated), db: Session = Depends(database)):
        record = db.get(SyncRecord, (device.user_id, 'attachments', str(file_id)))
        if not record or record.deleted_at or not record.data.get('sha256'):
            raise HTTPException(404, 'File not found')
        blob = db.get(FileBlob, (device.user_id, record.data['sha256']))
        if not blob:
            raise HTTPException(404, 'File content unavailable')
        path = storage.blob(device.user_id, blob.sha256)
        if not path.exists():
            raise HTTPException(404, 'File content unavailable')
        return FileResponse(path, media_type='application/octet-stream', headers={'X-Content-SHA256': blob.sha256})

    @app.websocket('/api/ws')
    async def websocket(ws: WebSocket):
        await ws.accept()
        try:
            # Tokens travel in a bounded first frame, never in query strings/access logs.
            token = await asyncio.wait_for(ws.receive_text(), timeout=10)
            if len(token) > 4096:
                raise HTTPException(401)
            cursor = -1
            last_sent = 0.0
            while True:
                with sessions() as db:
                    device = token_device(token, db)
                    latest = db.scalar(select(func.max(SyncChange.seq)).where(SyncChange.user_id == device.user_id)) or 0
                if latest != cursor:
                    await ws.send_json({'type': 'sync_available', 'latest_cursor': latest})
                    cursor = latest
                    last_sent = time.monotonic()
                elif time.monotonic() - last_sent >= WS_HEARTBEAT_SECONDS:
                    await ws.send_json({'type': 'heartbeat'})
                    last_sent = time.monotonic()
                await asyncio.sleep(WS_POLL_SECONDS)
        except (WebSocketDisconnect, HTTPException, asyncio.TimeoutError, RuntimeError):
            try:
                await ws.close(code=1008)
            except RuntimeError:
                pass

    return app
