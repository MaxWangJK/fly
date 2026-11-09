from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect


def test_alembic_upgrade_and_downgrade(tmp_path, monkeypatch):
    path = tmp_path / 'migration.db'
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(path))
    monkeypatch.setenv('APP_ENV', 'test')
    monkeypatch.setenv('JWT_PRIVATE_SECRET', 'development-migration-secret-at-least-32')
    config = Config('alembic.ini')
    command.upgrade(config, 'head')
    engine = create_engine('sqlite:///' + str(path))
    assert set(inspect(engine).get_table_names()) >= {
        'users', 'devices', 'refresh_tokens', 'sync_records', 'sync_changes',
        'processed_mutations', 'sync_conflicts', 'file_blobs', 'file_upload_sessions',
        'account_deletion_cleanup', 'alembic_version',
        'analytics_devices', 'analytics_daily_active'}
    command.downgrade(config, 'base')
    assert inspect(engine).get_table_names() == ['alembic_version']


def test_postgresql_migration_sql_contains_jsonb_and_sequence(tmp_path, monkeypatch):
    from io import StringIO
    monkeypatch.setenv('DATABASE_URL', 'postgresql+psycopg://fly:test@localhost/fly')
    monkeypatch.setenv('APP_ENV', 'test')
    monkeypatch.setenv('JWT_PRIVATE_SECRET', 'development-migration-secret-at-least-32')
    output = StringIO()
    config = Config('alembic.ini', output_buffer=output)
    command.upgrade(config, 'head', sql=True)
    sql = output.getvalue()
    assert 'JSONB' in sql and 'BIGSERIAL' in sql


def test_upgrade_preserves_existing_user_record_and_versions(tmp_path, monkeypatch):
    from sqlalchemy.orm import Session
    from app.schema_v1 import User as OldUser, Device as OldDevice, SyncRecord as OldRecord
    from app.models import SyncRecord
    path = tmp_path / 'retained.db'
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(path))
    monkeypatch.setenv('APP_ENV', 'test')
    monkeypatch.setenv('JWT_PRIVATE_SECRET', 'development-migration-secret-at-least-32')
    config = Config('alembic.ini')
    command.upgrade(config, '0001')
    engine = create_engine('sqlite:///' + str(path))
    with Session(engine) as db:
        user = OldUser(email='retained@example.com', password_hash='retained-test-hash')
        db.add(user); db.flush()
        device = OldDevice(user_id=user.id, device_name='Retained', device_type='desktop', platform='windows', app_version='2.0.6')
        db.add(device); db.flush()
        record = OldRecord(user_id=user.id, entity_type='customers', record_id='retained-id', version=7,
                           data={'name': 'Retained customer'}, last_device_id=device.id)
        db.add(record); db.commit()
        user_id = user.id
    command.upgrade(config, 'head')
    with Session(engine) as db:
        record = db.get(SyncRecord, (user_id, 'customers', 'retained-id'))
        assert record.version == 7 and record.data == {'name': 'Retained customer'}
        assert record.field_clocks == {}
