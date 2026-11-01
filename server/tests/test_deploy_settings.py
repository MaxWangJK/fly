import importlib.util
from pathlib import Path
import re

import pytest


spec = importlib.util.spec_from_file_location('prepare_cloud', Path(__file__).parents[1] / 'deploy/prepare_cloud.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_fresh_settings_share_database_password_and_keep_cloud_files_off(tmp_path, capsys):
    output = tmp_path / '.env'
    module.prepare(output)
    values = dict(line.split('=', 1) for line in output.read_text().splitlines())
    password = values['POSTGRES_PASSWORD']
    assert re.fullmatch('[0-9a-f]{64}', password)
    assert re.fullmatch('[0-9a-f]{64}', values['JWT_PRIVATE_SECRET'])
    assert password != values['JWT_PRIVATE_SECRET']
    assert values['DATABASE_URL'] == f'postgresql+psycopg://fly:{password}@postgres/fly'
    assert values['CLOUD_FILE_TRANSFER_ENABLED'] == 'false'
    assert values['ALLOW_PASSWORD_AUTH'] == 'true'
    assert values['COMPOSE_PROJECT_NAME'] == 'fly-sync'
    assert not capsys.readouterr().out


def test_preparation_refuses_to_replace_existing_database_identity(tmp_path):
    output = tmp_path / '.env'
    output.write_text('original settings')
    with pytest.raises(FileExistsError):
        module.prepare(output)
    assert output.read_text() == 'original settings'


@pytest.mark.parametrize('domain', ['https://world-workshop.cn', 'example.com\nALLOW_PASSWORD_AUTH=false', '../local'])
def test_preparation_rejects_invalid_hostnames(tmp_path, domain):
    with pytest.raises(ValueError):
        module.prepare(tmp_path / '.env', domain)
    assert not (tmp_path / '.env').exists()
