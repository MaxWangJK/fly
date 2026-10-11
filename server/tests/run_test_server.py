"""Ephemeral localhost backend for Flutter's two-device protocol test."""
from pathlib import Path
import tempfile
import uvicorn
from sqlalchemy import create_engine
from app.config import Settings
from app.main import create_app
from app.models import Base

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='fly-two-client-') as directory:
        root = Path(directory)
        print('Ephemeral test root:', root, flush=True)
        engine = create_engine('sqlite:///' + str(root / 'test.db'), connect_args={'check_same_thread': False})
        Base.metadata.create_all(engine)
        settings = Settings(database_url='sqlite://', app_env='test',
            jwt_private_secret='development-ephemeral-test-secret-32-characters', storage_root=root / 'blobs')
        uvicorn.run(create_app(settings, engine), host='127.0.0.1', port=18765, access_log=False)
