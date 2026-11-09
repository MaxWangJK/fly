from datetime import datetime, timedelta, timezone
import logging

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine, inspect, select, func
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import Session, sessionmaker

from app.config import Settings
from app.main import create_app
from app.models import AnalyticsDevice, AnalyticsDailyActive, Base
from app.analytics import AnalyticsAccessLogFilter
import app.analytics as analytics

ADMIN = ('stats-owner', 'isolated-admin-password-for-tests')


@pytest.fixture
def api(tmp_path, monkeypatch):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='development-analytics-test-secret-32-characters', app_env='test',
        database_url='sqlite://', storage_root=tmp_path / 'blobs', release_directory=tmp_path / 'releases',
        analytics_admin_username=ADMIN[0], analytics_admin_password=ADMIN[1])
    clock = [datetime(2026, 11, 9, 4, tzinfo=timezone.utc)]
    monkeypatch.setattr(analytics, 'now', lambda: clock[0])
    with TestClient(create_app(settings, engine)) as client:
        yield client, engine, clock


def overview(client):
    result = client.get('/api/admin/stats/overview', auth=ADMIN)
    assert result.status_code == 200, result.text
    assert result.headers['cache-control'] == 'no-store'
    return result.json()


def test_install_action_and_duplicate_install(api):
    client, engine, _ = api
    for _ in range(10):
        result = client.post('/api/stats/ABC12345/1')
        assert result.status_code == 200 and result.content == b''
    data = overview(client)
    assert data['total_installs'] == data['today_installs'] == 1
    assert data['today_active'] == 0
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(AnalyticsDevice)) == 1


def test_open_action_duplicate_daily_open_and_open_without_install(api):
    client, engine, clock = api
    for _ in range(10):
        assert client.post('/api/stats/NEWOPEN88/2').status_code == 200
    assert client.post('/api/stats/NEWOPEN88/1').status_code == 200
    clock[0] += timedelta(days=1)
    client.post('/api/stats/NEWOPEN88/2')
    data = overview(client)
    assert data['total_installs'] == data['today_active'] == data['yesterday_active'] == 1
    assert data['last_7_days_active_unique'] == 1
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(AnalyticsDailyActive)) == 2


@pytest.mark.parametrize('action', ['0', '3', '-1', 'install', 'open', '01', '1.0'])
def test_invalid_action(api, action):
    assert api[0].post(f'/api/stats/ABC12345/{action}').status_code == 400


@pytest.mark.parametrize('code', ['short', 'x' * 33, 'abc-12345', 'abc_12345', 'abc%20defg', '%E6%B5%8B%E8%AF%95test'])
def test_invalid_device_code(api, code):
    assert api[0].post(f'/api/stats/{code}/1').status_code == 400


def test_rejects_extra_body_and_query(api):
    assert api[0].post('/api/stats/ABC12345/1', json={'email': 'not-stored@example.test'}).status_code == 400
    assert api[0].post('/api/stats/ABC12345/1?platform=windows').status_code == 400
    assert overview(api[0])['total_installs'] == 0


@pytest.mark.parametrize('days', [1, 7, 30])
def test_retention_exact_return_date_and_unmature_excluded(api, days):
    client, _, clock = api
    first = clock[0]
    for code in ['RETURNS1', 'RETURNS2']:
        client.post(f'/api/stats/{code}/1')
    # Returning only on a nearby day is not D7/D30 (or D1).
    clock[0] = first + timedelta(days=days - 1)
    client.post('/api/stats/RETURNS2/2')
    clock[0] = first + timedelta(days=days)
    client.post('/api/stats/RETURNS1/2')
    client.post('/api/stats/TOOYOUNG/1')
    data = overview(client)
    assert data['retention'][f'd{days}'] == {'eligible_installs': 2, 'retained': 1, 'rate_percent': 50.0}


def test_server_shanghai_midnight_and_unique_windows(api):
    client, _, clock = api
    clock[0] = datetime(2026, 11, 8, 15, 59, tzinfo=timezone.utc)
    client.post('/api/stats/MIDNIGHT/2')
    clock[0] += timedelta(minutes=2)
    client.post('/api/stats/MIDNIGHT/2')
    client.post('/api/stats/ANOTHER8/2')
    data = overview(client)
    assert data['server_date'] == '2026-11-09'
    assert data['today_active'] == 2 and data['yesterday_active'] == 1
    assert data['last_7_days_active_unique'] == data['last_30_days_active_unique'] == 2
    assert data['today_installs'] == 1
    assert len(data['trends']) == 30
    assert data['trends'][-1] == {'date': '2026-11-09', 'installs': 1, 'active': 2}


def test_admin_auth_and_empty_cohort(api):
    client = api[0]
    for path in ['/api/admin/stats', '/api/admin/stats/overview']:
        assert client.get(path).status_code == 401
        assert client.get(path, auth=('wrong', 'wrong')).status_code == 401
    dashboard = client.get('/api/admin/stats', auth=ADMIN)
    assert dashboard.status_code == 200
    assert '__NONCE__' not in dashboard.text
    assert 'frame-ancestors' in dashboard.headers['content-security-policy']
    data = overview(client)
    assert data['retention']['d1']['rate_percent'] is None


def test_schema_and_logs_do_not_link_content_ip_or_account(api):
    client, engine, _ = api
    client.post('/api/stats/ANON8888/2', headers={'X-Forwarded-For': '192.0.2.1', 'Authorization': 'Bearer private-account'})
    schema = inspect(engine)
    assert {c['name'] for c in schema.get_columns('analytics_devices')} == {
        'device_code', 'first_seen_at', 'last_seen_at', 'created_at'}
    assert {c['name'] for c in schema.get_columns('analytics_daily_active')} == {
        'id', 'device_code', 'active_date', 'created_at'}
    assert not schema.get_foreign_keys('analytics_devices')
    assert 'ANON8888' not in str(overview(client))
    filter_ = AnalyticsAccessLogFilter()
    args = ('192.0.2.1:1234', 'POST', '/api/stats/ANON8888/2', '1.1', 200)
    assert not filter_.filter(logging.LogRecord('uvicorn.access', 20, '', 0, '%s - "%s %s HTTP/%s" %d', args, None))
    assert not filter_.filter(logging.LogRecord('uvicorn.access', 20, '', 0, 'POST /api/%73tats/ANON8888/2', (), None))
    assert filter_.filter(logging.LogRecord('uvicorn.access', 20, '', 0, 'GET /api/health', (), None))


def test_concurrent_reports_use_database_uniqueness(tmp_path):
    from concurrent.futures import ThreadPoolExecutor
    engine = create_engine('sqlite:///' + str(tmp_path / 'concurrent.db'),
                           connect_args={'check_same_thread': False, 'timeout': 15})
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine)
    try:
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda action: analytics.record_action(sessions, 'CONCURRENT88', action), [1, 2] * 10))
        with sessions() as db:
            assert db.scalar(select(func.count()).select_from(AnalyticsDevice)) == 1
            assert db.scalar(select(func.count()).select_from(AnalyticsDailyActive)) == 1
    finally:
        engine.dispose()
