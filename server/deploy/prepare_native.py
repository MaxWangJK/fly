"""Create native Ubuntu settings using an existing PostgreSQL user/database."""
import argparse
from getpass import GetPassWarning, getpass
import ipaddress
import os
from pathlib import Path
import re
import secrets
import warnings
from urllib.parse import quote


def prepare(output: Path, password: str, domain='world-workshop.cn',
            database_host='127.0.0.1', database_port=5432):
    # Names are fixed to fly for the short setup guide. Existing installations
    # may instead retain their own DATABASE_URL in the original .env.
    if not password or '\x00' in password:
        raise ValueError('A non-empty PostgreSQL password is required')
    if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', domain):
        raise ValueError('Use a domain without protocol, path or port')
    try:
        host = str(ipaddress.ip_address(database_host))
        if ':' in host:
            host = f'[{host}]'
    except ValueError:
        if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', database_host):
            raise ValueError('Invalid PostgreSQL hostname or IP address') from None
        host = database_host
    if not 1 <= database_port <= 65535:
        raise ValueError('Database port must be between 1 and 65535')
    content = '\n'.join([
        f'DATABASE_URL=postgresql+psycopg://fly:{quote(password, safe="")}@{host}:{database_port}/fly',
        f'JWT_PRIVATE_SECRET={secrets.token_hex(32)}',
        'APP_ENV=production',
        'STORAGE_ROOT=/var/lib/fly/storage',
        f'ALLOWED_HOSTS={domain},localhost,127.0.0.1',
        'CORS_ORIGINS=',
        'CLOUD_FILE_TRANSFER_ENABLED=false',
        'ALLOW_PASSWORD_AUTH=true',
        'DEVICE_ENROLLMENT_ENABLED=true',
        'SMTP_CONFIG_FILE=/opt/fly-sync/server/private/smtp.json',
        'FILE_SYNC_ALLOWED_EMAILS=',
        'ANALYTICS_ADMIN_USERNAME=admin',
        'ANALYTICS_ADMIN_PASSWORD=',
        'RELEASE_DIRECTORY=/var/www/fly/public/downloads', '',
    ])
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as stream:
        stream.write(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('.env'))
    parser.add_argument('--domain', default='world-workshop.cn')
    parser.add_argument('--db-host', default='127.0.0.1')
    parser.add_argument('--db-port', type=int, default=5432)
    args = parser.parse_args()
    if args.output.exists():
        parser.exit(1, 'Settings already exist. Keep the original database credentials and JWT secret.\n')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', GetPassWarning)
            password = getpass('Password of the existing PostgreSQL user fly (hidden): ')
        prepare(args.output, password, args.domain, args.db_host, args.db_port)
    except (EOFError, KeyboardInterrupt):
        parser.exit(1, '\nSetup cancelled; no settings were replaced.\n')
    except GetPassWarning:
        parser.exit(1, 'Run setup from an interactive SSH terminal so the password stays hidden.\n')
    except (FileExistsError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Created {args.output}. No secrets printed. Keep it for all later updates.')


if __name__ == '__main__':
    main()
