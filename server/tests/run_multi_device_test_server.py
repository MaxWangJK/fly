"""Isolated integration server; enrollment codes are written only to a test file."""
import json
import os
from pathlib import Path
import tempfile
import uvicorn
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.config import Settings
from app.enrollment import create_sync_user, issue_device_code
from app.main import create_app
from app.models import Base

if __name__ == '__main__':
    output = Path(os.environ['FLY_SYNC_TEST_ENROLLMENT_FILE'])
    with tempfile.TemporaryDirectory(prefix='fly-three-device-') as directory:
        root = Path(directory)
        engine = create_engine('sqlite:///' + str(root / 'test.db'), connect_args={'check_same_thread': False})
        Base.metadata.create_all(engine)
        with Session(engine) as db:
            user = create_sync_user(db)
            codes = [issue_device_code(db, user.id, minutes=60) for _ in range(3)]
            db.commit()
        output.write_text(json.dumps({'codes': codes}), encoding='utf-8')
        settings = Settings(database_url='sqlite://', app_env='test',
            jwt_private_secret='development-isolated-three-device-secret-32', storage_root=root / 'blobs')
        try:
            uvicorn.run(create_app(settings, engine), host='127.0.0.1',
                        port=int(os.environ.get('FLY_SYNC_TEST_PORT', '18767')), access_log=False)
        finally:
            engine.dispose()
            output.unlink(missing_ok=True)
