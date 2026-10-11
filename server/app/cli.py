"""Small operator CLI; no passwords, tokens or business payloads printed."""
import argparse
from uuid import UUID
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from .config import Settings
from .models import Device, FileBlob, User, now


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['stats', 'revoke-device'])
    parser.add_argument('--device-id', type=UUID)
    args = parser.parse_args()
    with Session(create_engine(Settings().database_url)) as db:
        if args.command == 'stats':
            print('users:', db.scalar(select(func.count()).select_from(User)))
            print('blob bytes:', db.scalar(select(func.coalesce(func.sum(FileBlob.size), 0))))
        else:
            if args.device_id is None:
                parser.error('--device-id is required')
            device = db.get(Device, str(args.device_id))
            if device is None:
                parser.error('device not found')
            device.revoked_at = now()
            db.commit()
            print('device revoked')


if __name__ == '__main__':
    main()
