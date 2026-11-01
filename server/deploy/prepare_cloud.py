"""Create fresh production settings without printing secrets or replacing data."""
import argparse
import os
from pathlib import Path
import re
import secrets


def prepare(output: Path, domain: str = 'world-workshop.cn'):
    if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', domain):
        raise ValueError('Use a hostname without protocol, path or port')
    password, signing_secret = secrets.token_hex(32), secrets.token_hex(32)
    content = '\n'.join([
        'COMPOSE_PROJECT_NAME=fly-sync',
        f'POSTGRES_PASSWORD={password}',
        f'DATABASE_URL=postgresql+psycopg://fly:{password}@postgres/fly',
        f'JWT_PRIVATE_SECRET={signing_secret}',
        'APP_ENV=production', 'STORAGE_ROOT=/var/lib/fly/storage',
        f'ALLOWED_HOSTS={domain},localhost,127.0.0.1', 'CORS_ORIGINS=',
        'CLOUD_FILE_TRANSFER_ENABLED=false', 'ALLOW_PASSWORD_AUTH=true',
        'DEVICE_ENROLLMENT_ENABLED=true',
        'SMTP_CONFIG_FILE=/run/fly/private/smtp.json',
        'FILE_SYNC_ALLOWED_EMAILS=', ''
    ])
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as stream:
        stream.write(content)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('.env'))
    parser.add_argument('--domain', default='world-workshop.cn')
    args = parser.parse_args()
    try:
        prepare(args.output, args.domain)
    except FileExistsError:
        parser.exit(1, 'Settings already exist; keep the original credentials and project/volume identity.\n')
    except ValueError as error:
        parser.error(str(error))
    print(f'Created {args.output}. Secrets were not printed. Keep this file for later updates.')
