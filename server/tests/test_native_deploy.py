"""Native config and a real migrated Python process, with no production server."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen

import pytest
from sqlalchemy.engine import make_url

from app.config import Settings

SERVER = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('prepare_native', SERVER / 'deploy/prepare_native.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def test_native_config_roundtrips_special_passwords_and_is_readable_by_settings(tmp_path, capsys):
    password = 'isolated:@/%$#" password\\test'
    output = tmp_path / '.env'
    native.prepare(output, password)
    settings = Settings(_env_file=output)
    url = make_url(settings.database_url)
    assert (url.username, url.password, url.host, url.port, url.database) == ('fly', password, '127.0.0.1', 5432, 'fly')
    assert settings.cloud_file_transfer_enabled is False
    assert settings.allow_password_auth is True
    assert len(settings.jwt_private_secret) == 64
    assert settings.smtp_config_file.as_posix() == '/opt/fly-sync/server/private/smtp.json'
    assert settings.release_directory.as_posix() == '/var/www/fly/public/downloads'
    assert not settings.analytics_admin_password.get_secret_value()
    assert password not in output.read_text()
    assert not capsys.readouterr().out
    if os.name != 'nt':
        assert output.stat().st_mode & 0o777 == 0o600


@pytest.mark.parametrize('host', ['localhost', '192.168.0.21', '::1', 'db.internal.example'])
def test_native_database_host_and_port(tmp_path, host):
    output = tmp_path / '.env'
    native.prepare(output, 'isolated-password', database_host=host, database_port=5433)
    settings = Settings(_env_file=output)
    url = make_url(settings.database_url)
    assert url.host == host and url.port == 5433
    assert 'COMPOSE_' not in output.read_text()


@pytest.mark.parametrize('options', [
    {'password': ''}, {'database_host': 'localhost\nAPP_ENV=test'},
    {'domain': 'https://world-workshop.cn'}, {'database_port': 0},
    {'database_port': 65536},
])
def test_invalid_native_settings_leave_no_file(tmp_path, options):
    output = tmp_path / '.env'
    with pytest.raises(ValueError):
        native.prepare(output, **{'password': 'isolated-password', **options})
    assert not output.exists()


def test_native_cli_refuses_to_replace_existing_credentials_without_prompting(tmp_path):
    output = tmp_path / '.env'
    original = 'JWT_PRIVATE_SECRET=original-private-value\n'
    output.write_text(original)
    result = subprocess.run([sys.executable, str(SERVER / 'deploy/prepare_native.py'), '--output', str(output)],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
    assert result.returncode == 1
    assert 'already exist' in result.stderr
    assert output.read_text() == original
    assert 'original-private-value' not in result.stdout + result.stderr


def test_native_python_start_migrates_and_serves_health_from_env(tmp_path):
    # Use the same public source and venv Python as deployment, with an isolated
    # SQLite database. PostgreSQL/systemd themselves need Ubuntu acceptance.
    for folder in ('app', 'alembic'):
        shutil.copytree(SERVER / folder, tmp_path / folder, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(SERVER / 'alembic.ini', tmp_path / 'alembic.ini')
    output = tmp_path / '.env'
    native.prepare(output, 'isolated-password')
    output.write_text(output.read_text().replace(
        make_url(Settings(_env_file=output).database_url).render_as_string(hide_password=False),
        'sqlite:///' + (tmp_path / 'native-test.db').as_posix()).replace(
        'STORAGE_ROOT=/var/lib/fly/storage', f'STORAGE_ROOT={tmp_path.as_posix()}/storage'))
    env = {key: value for key, value in os.environ.items() if key not in Settings.model_fields and key.lower() not in Settings.model_fields}
    migrated = subprocess.run([sys.executable, '-m', 'alembic', 'upgrade', 'head'], cwd=tmp_path,
        env=env, capture_output=True, text=True, timeout=40)
    assert migrated.returncode == 0, migrated.stderr
    with socket.socket() as port_socket:
        port_socket.bind(('127.0.0.1', 0))
        port = port_socket.getsockname()[1]
    with (tmp_path / 'service.log').open('wb') as log:
        process = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app.asgi:app',
            '--host', '127.0.0.1', '--port', str(port), '--workers', '1',
            '--proxy-headers', '--forwarded-allow-ips=127.0.0.1'],
            cwd=tmp_path, env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    with urlopen(f'http://127.0.0.1:{port}/api/health', timeout=1) as response:
                        health = json.load(response)
                    break
                except URLError:
                    if process.poll() is not None or time.monotonic() >= deadline:
                        pytest.fail('Native Python process did not become healthy')
                    time.sleep(0.1)
            assert health['status'] == 'ok'
            assert health['capabilities']['passwordReset'] is True
            assert health['capabilities']['deleteAccount'] is True
            assert health['capabilities']['fileContents'] is False
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
