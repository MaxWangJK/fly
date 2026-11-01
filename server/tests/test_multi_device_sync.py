from datetime import timedelta
import hashlib
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.enrollment import create_sync_user, issue_device_code
from app.main import create_app
from app.models import Base, Device, DeviceEnrollmentCode, SyncConflict, now


def test_three_enrolled_devices_merge_offline_edits_without_user_conflicts(tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='multi-device-test-secret-at-least-32-characters', app_env='test',
                        database_url='sqlite://', storage_root=tmp_path)
    with Session(engine) as db:
        user = create_sync_user(db)
        other = create_sync_user(db)
        codes = [issue_device_code(db, user.id) for _ in range(3)]
        other_code = issue_device_code(db, other.id)
        expired = issue_device_code(db, user.id)
        row = db.get(DeviceEnrollmentCode, hashlib.sha256(expired.encode()).hexdigest())
        row.expires_at = now() - timedelta(seconds=1)
        db.commit()
    with TestClient(create_app(settings, engine)) as api:
        sessions = []
        for code, name in zip(codes, ['Work computer', 'Work phone', 'Home computer']):
            response = api.post('/api/sync/enroll-device', json={'code': code, 'deviceName': name})
            assert response.status_code == 200, response.text
            sessions.append(response.json())
        assert len({s['deviceId'] for s in sessions}) == 3
        assert len({s['userId'] for s in sessions}) == 1
        assert api.post('/api/sync/enroll-device', json={'code': codes[0], 'deviceName': 'Replay'}).status_code == 401
        assert api.post('/api/sync/enroll-device', json={'code': expired, 'deviceName': 'Expired'}).status_code == 401
        assert api.post('/api/sync/enroll-device', json={'code': 'x'*40, 'deviceName': 'Wrong'}).status_code == 401
        outsider = api.post('/api/sync/enroll-device', json={'code': other_code, 'deviceName': 'Other user'}).json()

        def headers(session): return {'Authorization': 'Bearer ' + session['accessToken']}

        def push(session, rid, base, payload, clocks, operation='upsert'):
            mid = str(uuid4())
            body = {'mutationId': mid, 'recordId': rid, 'entityType': 'customers', 'baseVersion': base,
                    'operation': operation, 'payload': payload, 'changedFields': list(payload),
                    'fieldClocks': {k: [v, mid] for k, v in clocks.items()}}
            result = api.post('/api/sync/push', headers=headers(session), json={'mutations': [body]})
            assert result.status_code == 200, result.text
            ack = result.json()['results'][0]
            assert api.post('/api/sync/push', headers=headers(session), json={'mutations': [body]}).json()['results'][0] == ack
            return ack

        rid = str(uuid4())
        push(sessions[0], rid, 0, {'name': 'Shared customer', 'phone': '', 'address': ''},
             {'name': 1000, 'phone': 1000, 'address': 1000})
        push(sessions[2], rid, 1, {'address': 'Home edit', 'phone': 'Newer phone'}, {'address': 5000, 'phone': 5000})
        # Work PC was offline with base 1. Its distinct field survives, while
        # an older phone edit arriving later cannot overwrite the newer edit.
        merged = push(sessions[0], rid, 1, {'company': 'Work company', 'phone': 'Older offline phone'},
                      {'company': 4000, 'phone': 3000})
        assert merged['status'] == 'accepted' and merged['autoMerged']
        assert merged['record']['data'] == {'name': 'Shared customer', 'phone': 'Newer phone',
                                            'address': 'Home edit', 'company': 'Work company'}
        # A causal edit intentionally clearing a value is preserved even with
        # a backwards clock; the returned clock remains monotonic.
        cleared = push(sessions[1], rid, 3, {'phone': ''}, {'phone': 2000})
        assert cleared['record']['data']['phone'] == ''
        assert cleared['record']['fieldClocks']['phone'][0] > 5000
        for session, name in zip(sessions, ['Work-only customer', 'Phone-only customer', 'Home-only customer']):
            push(session, str(uuid4()), 0, {'name': name}, {'name': 6000})
        for session in sessions:
            page = api.get('/api/sync/pull', headers=headers(session)).json()
            folded = {r['recordId']: r for r in page['changes']}
            assert len(folded) == 4
            assert folded[rid]['data']['phone'] == ''
            assert api.get('/api/sync/conflicts', headers=headers(session)).json() == []
            for method, path, kwargs in [
                ('post', '/api/files/upload/init', {'json': {'sha256': 'a'*64, 'size': 1}}),
                ('get', f'/api/files/{uuid4()}/download', {}),
                ('put', f'/api/files/upload/{uuid4()}/chunk?offset=0', {'content': b'a'}),
                ('post', f'/api/files/upload/{uuid4()}/complete', {}),
            ]:
                assert getattr(api, method)(path, headers=headers(session), **kwargs).status_code == 403
        assert api.get('/api/sync/pull', headers=headers(outsider)).json()['changes'] == []
        assert api.post('/api/auth/register', json={'email': 'test@example.com', 'password': 'long-test-password',
                        'deviceName': 'No signup'}).status_code == 422
        assert api.post('/api/auth/login', json={'email': 'test@example.com', 'password': 'long-test-password',
                        'deviceName': 'No login'}).status_code == 401
        assert api.get('/api/health').json()['capabilities']['fileContents'] is False
        target = sessions[1]['deviceId']
        assert api.post(f'/api/devices/{target}/revoke', headers=headers(sessions[0])).status_code == 200
        assert api.get('/api/sync/pull', headers=headers(sessions[1])).status_code == 401
        assert api.post('/api/auth/refresh', json={'refreshToken': sessions[1]['refreshToken']}).status_code == 401
    with Session(engine) as db:
        assert db.scalars(select(SyncConflict)).one().resolved_at is not None
        assert len(db.scalars(select(Device).where(Device.user_id == sessions[0]['userId'])).all()) == 3
