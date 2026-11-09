import hashlib

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.main import create_app
from app.models import Base
from app.updates import ReleaseCatalog


def test_catalog_numeric_versions_platforms_and_testing_files(tmp_path):
    for name in ['Fly-2.9.exe', 'Fly-2.10.exe', 'Fly-3.0.apk', 'Fly-Setup-2.0.20-build56-testing.exe',
                 'Fly-9.0.exe.part', 'Fly-999.0-beta.exe', 'Fly-8.0-android.exe']:
        (tmp_path / name).write_bytes(name.encode())
    catalog = ReleaseCatalog(tmp_path)
    (tmp_path / 'Fly-999.0.exe').touch()  # Incomplete zero-byte upload is not a release.
    assert catalog.latest('windows').path.name == 'Fly-2.10.exe'
    assert catalog.latest('android').path.name == 'Fly-3.0.apk'
    (tmp_path / 'Fly-2.10-build57.exe').write_bytes(b'new')
    latest = catalog.latest('windows')
    assert latest.build == 57
    meta = catalog.metadata(latest)
    assert meta['version'] == '2.10.0'
    assert meta['sha256'] == hashlib.sha256(b'new').hexdigest()


def test_update_lookup_download_and_no_candidate(tmp_path):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    settings = Settings(jwt_private_secret='development-update-secret-at-least-32-characters', app_env='test',
                        database_url='sqlite://', storage_root=tmp_path / 'storage', release_directory=tmp_path / 'downloads')
    with TestClient(create_app(settings, engine)) as client:
        assert client.get('/api/updates/latest/windows').json() == {'latest': None}
        settings.release_directory.mkdir()
        (settings.release_directory / 'Fly-3.0.exe').write_bytes(b'test installer')
        result = client.get('/api/updates/latest/windows')
        assert result.status_code == 200 and result.headers['cache-control'] == 'no-store'
        data = result.json()['latest']
        assert data['version'] == '3.0.0'
        assert client.get(data['downloadPath']).content == b'test installer'
        assert client.get('/api/updates/latest/unsupported').status_code == 400
        assert client.get('/api/updates/download/secrets.json').status_code == 404
        assert client.get('/api/admin/stats').status_code == 404
        assert client.get('/api/admin/stats/overview').status_code == 404
