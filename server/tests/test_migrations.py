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
        'processed_mutations', 'sync_conflicts', 'file_blobs', 'file_upload_sessions', 'alembic_version'}
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
