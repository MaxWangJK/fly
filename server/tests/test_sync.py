import hashlib
from pathlib import Path
from uuid import uuid4
import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.pool import StaticPool
from app.config import Settings
from app.main import create_app
from app.models import Base, Device, ProcessedMutation, RefreshToken, SyncConflict, SyncRecord, User


@pytest.fixture
def client(tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='development-test-secret-at-least-32-characters', app_env='test',
                        database_url='sqlite://', storage_root=tmp_path)
    with TestClient(create_app(settings, engine)) as api:
        yield api


def credentials(email='max@example.com'):
    return {'email': email, 'password': 'a-long-secret-password', 'deviceName': 'Test PC'}


def register(client, email='max@example.com'):
    response = client.post('/api/auth/register', json=credentials(email))
    assert response.status_code == 201, response.text
    return response.json()


def headers(session):
    return {'Authorization': 'Bearer ' + session['accessToken']}


def mutation(record=None, base=0, payload=None, fields=None, operation='upsert', entity='customers'):
    payload = payload or {'name': 'Jack', 'phone': '', 'address': ''}
    return {'mutationId': str(uuid4()), 'entityType': entity, 'recordId': record or str(uuid4()),
            'baseVersion': base, 'payload': payload, 'changedFields': list(payload) if fields is None else fields,
            'operation': operation}


def push(client, session, *mutations):
    response = client.post('/api/sync/push', headers=headers(session), json={'mutations': list(mutations)})
    assert response.status_code == 200, response.text
    return response.json()['results']


def test_auth_normalization_and_rotation(client):
    session = register(client, ' Max@Example.com ')
    assert client.post('/api/auth/register', json=credentials('MAX@example.com')).status_code == 409
    wrong = credentials(); wrong['password'] = 'wrong-password-long'
    assert client.post('/api/auth/login', json=wrong).status_code == 401
    token = session['refreshToken']
    fresh = client.post('/api/auth/refresh', json={'refreshToken': token})
    assert fresh.status_code == 200
    assert fresh.json()['refreshToken'] != token
    assert client.post('/api/auth/refresh', json={'refreshToken': token}).status_code == 401
    assert client.post('/api/auth/logout', headers=headers(fresh.json())).status_code == 200
    assert client.get('/api/account/me', headers=headers(fresh.json())).status_code == 401
    assert client.post('/api/auth/refresh', json={'refreshToken': fresh.json()['refreshToken']}).status_code == 401


def test_websocket_idle_heartbeat_and_following_change(client, monkeypatch):
    import app.main as main_module
    monkeypatch.setattr(main_module, 'WS_POLL_SECONDS', 0.01)
    monkeypatch.setattr(main_module, 'WS_HEARTBEAT_SECONDS', 0.03)
    account = register(client)
    with client.websocket_connect('/api/ws') as socket:
        socket.send_text(account['accessToken'])
        initial = socket.receive_json()
        assert initial == {'type': 'sync_available', 'latest_cursor': 0}
        assert socket.receive_json() == {'type': 'heartbeat'}
        push(client, account, mutation())
        for _ in range(30):
            event = socket.receive_json()
            if event['type'] == 'sync_available':
                assert event['latest_cursor'] > 0
                break
        else:
            pytest.fail('No change notification after heartbeat')


def test_server_addresses_allow_ip_domain_ipv6_and_custom_ports(client):
    settings = client.app.state.settings.model_copy(update={
        'allowed_hosts': ' 198.51.100.10, sync.example.com, 2001:db8::1, localhost, testserver '
    })
    with TestClient(create_app(settings, client.app.state.engine)) as configured:
        for host in ['198.51.100.10:8080', 'sync.example.com:8443', '[2001:db8::1]:8080', 'localhost']:
            assert configured.get('/api/health', headers={'Host': host}).status_code == 200
        assert configured.get('/api/health', headers={'Host': 'untrusted.example.com'}).status_code == 400
        assert configured.get('/api/health', headers={'Host': 'www.sync.example.com'}).status_code == 400


def test_auth_hashes_and_invalid_expired_tokens(client):
    session = register(client)
    from sqlalchemy.orm import Session
    with Session(client.app.state.engine) as db:
        user = db.scalar(select(User))
        assert user.password_hash.startswith('$argon2id$')
        assert db.scalar(select(RefreshToken)).token_hash != session['refreshToken']
    assert client.get('/api/account/me', headers={'Authorization': 'Bearer invalid'}).status_code == 401
    token = jwt.encode({'sub': session['userId'], 'device': session['deviceId'], 'iat': 0, 'exp': 1,
                        'iss': 'fly-sync', 'aud': 'fly-client'}, client.app.state.settings.jwt_private_secret, algorithm='HS256')
    assert client.get('/api/account/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401


def test_multi_device_union_merge_conflict_cursor_idempotency(client):
    a = register(client)
    b = client.post('/api/auth/login', json=credentials()).json()
    first = mutation()
    ack = push(client, a, first)[0]
    assert ack['record']['version'] == 1
    assert push(client, a, first)[0] == ack
    original = client.get('/api/sync/pull', headers=headers(b)).json()
    assert original['changes'][0]['data']['name'] == 'Jack'
    rid = first['recordId']
    phone = mutation(rid, 1, {'phone': '123', 'updated_at': 10}, ['phone', 'updated_at'])
    address = mutation(rid, 1, {'address': 'Manila', 'updated_at': 2}, ['address', 'updated_at'])
    push(client, a, phone)
    merged = push(client, b, address)[0]
    assert merged['status'] == 'accepted'
    assert merged['record']['data']['phone'] == '123'
    assert merged['record']['data']['address'] == 'Manila'
    one = mutation(rid, 3, {'company': 'DEF'}, ['company'])
    two = mutation(rid, 3, {'company': 'XYZ'}, ['company'])
    push(client, a, one)
    conflict = push(client, b, two)[0]
    assert conflict['status'] == 'conflict'
    assert conflict['record']['data']['company'] == 'XYZ'
    saved = client.get('/api/sync/conflicts', headers=headers(a)).json()[0]
    assert saved['serverCandidate']['company'] == 'DEF'
    assert saved['localCandidate']['company'] == 'XYZ'
    tom = mutation(payload={'name': 'Tom'})
    push(client, b, tom)
    later = client.get('/api/sync/pull', params={'after': original['nextCursor'], 'limit': 2}, headers=headers(a)).json()
    assert len(later['changes']) == 2 and later['hasMore']
    all_records = client.get('/api/sync/bootstrap', headers=headers(a)).json()
    assert len(all_records['changes']) == 6


def test_delete_wins_explicit_restore(client):
    a = register(client)
    first = mutation()
    push(client, a, first)
    delete = mutation(first['recordId'], 1, fields=[], operation='delete')
    push(client, a, delete)
    stale = mutation(first['recordId'], 1, {'phone': 'offline'}, ['phone'])
    conflict = push(client, a, stale)[0]
    assert conflict['record']['deletedAt'] is not None
    assert conflict['record']['version'] == 2
    assert conflict['status'] == 'conflict'
    stale_restore = mutation(first['recordId'], 1, operation='restore')
    assert push(client, a, stale_restore)[0]['record']['deletedAt'] is not None
    restore = mutation(first['recordId'], 2, operation='restore')
    assert push(client, a, restore)[0]['record']['deletedAt'] is None


def test_isolation_id_reuse_and_atomic_batch(client):
    a = register(client)
    b = register(client, 'other@example.com')
    first = mutation()
    push(client, a, first)
    assert client.get('/api/sync/pull', headers=headers(b)).json()['changes'] == []
    altered = dict(first, payload={'name': 'Changed'}, changedFields=['name'])
    assert client.post('/api/sync/push', headers=headers(a), json={'mutations': [altered]}).status_code == 409
    valid = mutation()
    bad = mutation(base=99)
    assert client.post('/api/sync/push', headers=headers(a), json={'mutations': [valid, bad]}).status_code == 409
    assert len(client.get('/api/sync/pull', headers=headers(a)).json()['changes']) == 1
    assert client.post('/api/devices/' + a['deviceId'] + '/revoke', headers=headers(b)).status_code == 404


def test_files_resume_dedup_hash_and_user_isolation(client):
    a = register(client)
    b = register(client, 'other@example.com')
    content = b'file binary content'
    sha = hashlib.sha256(content).hexdigest()
    body = {'sha256': sha, 'size': len(content)}
    upload = client.post('/api/files/upload/init', headers=headers(a), json=body).json()
    upload_id = upload['uploadId']
    url = '/api/files/upload/' + upload_id
    assert client.put(url + '/chunk?offset=0', content=content[:5], headers=headers(a)).json()['offset'] == 5
    assert client.post('/api/files/upload/init', headers=headers(a), json=body).json()['offset'] == 5
    assert client.put(url + '/chunk?offset=0', content=content, headers=headers(a)).status_code == 409
    assert client.put(url + '/chunk?offset=5', content=content[5:], headers=headers(b)).status_code == 404
    assert client.put(url + '/chunk?offset=5', content=content[5:], headers=headers(a)).status_code == 200
    assert client.post(url + '/complete', headers=headers(a)).status_code == 200
    assert client.post(url + '/complete', headers=headers(a)).status_code == 200
    assert client.post('/api/files/upload/init', headers=headers(a), json=body).json()['exists']
    record = mutation(entity='attachments', payload={'id': 'file-business-id', 'sha256': sha, 'original_name': '../quote.txt'})
    push(client, a, record)
    url = '/api/files/' + record['recordId'] + '/download'
    assert client.get(url, headers=headers(a)).content == content
    assert client.get(url, headers=headers(b)).status_code == 404
    assert client.post('/api/files/upload/init', headers=headers(a), json={'sha256': '../traversal', 'size': 1}).status_code == 422
    assert client.post('/api/files/upload/init', headers=headers(a), json={'sha256': sha, 'size': 3 * 1024**3}).status_code == 413


def test_binary_conflict_preserves_both(client):
    a = register(client)
    first = mutation(entity='attachments', payload={'sha256': 'a' * 64, 'original_name': 'quote.xlsx'})
    push(client, a, first)
    push(client, a, mutation(first['recordId'], 1, {'sha256': 'b' * 64}, ['sha256'], entity='attachments'))
    result = push(client, a, mutation(first['recordId'], 1, {'sha256': 'c' * 64}, ['sha256'], entity='attachments'))[0]
    assert result['status'] == 'conflict'
    assert result['record']['data']['sha256'] == 'b' * 64
    conflict = client.get('/api/sync/conflicts', headers=headers(a)).json()[0]
    assert conflict['localCandidate']['sha256'] == 'c' * 64


def test_rate_limit_and_request_bound(client):
    for _ in range(10):
        client.post('/api/auth/login', json=credentials())
    assert client.post('/api/auth/login', json=credentials()).status_code == 429
    assert client.post('/api/sync/push', content=b'x' * (8 * 1024 * 1024 + 1)).status_code == 413


def test_bootstrap_35000_records_is_paged_and_complete(client):
    from sqlalchemy import insert
    from sqlalchemy.orm import Session
    from app.models import SyncChange
    account = register(client)
    rows = []
    for entity, count in [('customers', 10000), ('tasks', 10000), ('workspace_notes', 5000), ('attachments', 10000)]:
        for index in range(count):
            rows.append({'user_id': account['userId'], 'entity_type': entity, 'record_id': str(uuid4()),
                         'version': 1, 'data': {'title': f'Synthetic {index}'}, 'operation': 'upsert',
                         'changed_fields': ['title'], 'device_id': account['deviceId']})
    with Session(client.app.state.engine) as db:
        db.execute(insert(SyncChange), rows)
        db.commit()
    cursor, received = 0, set()
    while True:
        page = client.get('/api/sync/bootstrap', params={'after': cursor, 'limit': 200}, headers=headers(account)).json()
        assert len(page['changes']) <= 200
        received.update(change['recordId'] for change in page['changes'])
        assert page['nextCursor'] > cursor
        cursor = page['nextCursor']
        if not page['hasMore']:
            break
    assert len(received) == 35000


def test_note_and_binary_conflicts_create_distinct_copies(client):
    account = register(client)
    first = mutation(entity='note_blocks', payload={'id': str(uuid4()), 'note_id': str(uuid4()),
                    'content_json': 'original', 'sort_order': 0})
    push(client, account, first)
    push(client, account, mutation(first['recordId'], 1, {'content_json': 'A'}, ['content_json'], entity='note_blocks'))
    push(client, account, mutation(first['recordId'], 1, {'content_json': 'B'}, ['content_json'], entity='note_blocks'))
    changes = client.get('/api/sync/pull', headers=headers(account)).json()['changes']
    copies = [c for c in changes if c['recordId'] != first['recordId']]
    assert len(copies) == 1 and copies[0]['data']['content_json'] == 'A'
    file = mutation(entity='attachments', payload={'id': str(uuid4()), 'sha256': 'a' * 64, 'original_name': 'quote.xlsx'})
    push(client, account, file)
    push(client, account, mutation(file['recordId'], 1, {'sha256': 'b' * 64}, ['sha256'], entity='attachments'))
    push(client, account, mutation(file['recordId'], 1, {'sha256': 'c' * 64}, ['sha256'], entity='attachments'))
    changes = client.get('/api/sync/pull', headers=headers(account)).json()['changes']
    copies = [c for c in changes if c['entityType'] == 'attachments' and c['recordId'] != file['recordId']]
    assert len(copies) == 1 and copies[0]['data']['sha256'] == 'c' * 64
    assert 'conflict' in copies[0]['data']['original_name']


def test_delete_before_first_upload_retains_keys_for_other_devices(client):
    account = register(client)
    business_id = str(uuid4())
    deleted = mutation(payload={'id': business_id, 'name': 'Offline deleted'}, fields=[], operation='delete')
    ack = push(client, account, deleted)[0]
    assert ack['record']['data']['id'] == business_id
    assert ack['record']['deletedAt'] is not None
    stale = mutation(deleted['recordId'], 0, {'id': business_id, 'name': 'Offline edit'}, ['id', 'name'])
    result = push(client, account, stale)[0]
    assert result['status'] == 'conflict'
    assert result['record']['data']['id'] == business_id
    assert result['record']['deletedAt'] is not None
