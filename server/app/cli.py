"""Small operator CLI; no passwords, tokens or business payloads printed."""
import argparse
import os
from uuid import UUID
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from .config import Settings
from .models import Device, FileBlob, User, now
from .enrollment import create_sync_user, issue_device_code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['stats', 'revoke-device', 'create-sync-user', 'issue-device-code'])
    parser.add_argument('--device-id', type=UUID)
    parser.add_argument('--user-id', type=UUID)
    parser.add_argument('--output')
    parser.add_argument('--minutes', type=int, default=15)
    args = parser.parse_args()
    with Session(create_engine(Settings().database_url)) as db:
        if args.command == 'stats':
            print('users:', db.scalar(select(func.count()).select_from(User)))
            print('blob bytes:', db.scalar(select(func.coalesce(func.sum(FileBlob.size), 0))))
        elif args.command == 'create-sync-user':
            user = create_sync_user(db)
            db.commit()
            print('user ID:', user.id)
        elif args.command == 'issue-device-code':
            if not args.user_id or not args.output:
                parser.error('--user-id and --output are required; codes are not printed')
            code = issue_device_code(db, str(args.user_id), args.minutes)
            # Refuse to overwrite an existing secret; owner-only on Ubuntu.
            descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
                output.write(code + '\n')
            db.commit()
            print('one-use device code saved; valid for', args.minutes, 'minutes')
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
