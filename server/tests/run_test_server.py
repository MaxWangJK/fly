"""Ephemeral localhost backend for Flutter's two-device protocol test."""
from pathlib import Path
import os
import tempfile
import uvicorn
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from argon2 import PasswordHasher
from app.config import Settings
from app.main import create_app
from app.models import Base, User, now

if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='fly-two-client-') as directory:
        root = Path(directory)
        print('Ephemeral test root:', root, flush=True)
        engine = create_engine('sqlite:///' + str(root / 'test.db'), connect_args={'check_same_thread': False})
        Base.metadata.create_all(engine)
        # Protocol fixture; registration is tested separately with a fake mailbox.
        with Session(engine) as db:
            db.add(User(email='two-device@example.com', email_verified_at=now(),
                        password_hash=PasswordHasher().hash('two-client-password')))
            db.commit()
        settings = Settings(database_url='sqlite://', app_env='test',
            allow_password_auth=True, cloud_file_transfer_enabled=True,
            jwt_private_secret='development-ephemeral-test-secret-32-characters', storage_root=root / 'blobs')
        try:
            uvicorn.run(create_app(settings, engine), host='127.0.0.1',
                        port=int(os.environ.get('FLY_SYNC_TEST_PORT', '18765')), access_log=False)
        finally:
            engine.dispose()
