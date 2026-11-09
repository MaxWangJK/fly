from pathlib import Path
from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    database_url: str = 'postgresql+psycopg://fly:fly@postgres/fly'
    jwt_private_secret: str = Field(min_length=32)
    app_env: str = 'production'
    allowed_hosts: str = 'world-workshop.cn,localhost,127.0.0.1,testserver'
    cors_origins: str = ''
    storage_root: Path = Path('/var/lib/fly/storage')
    access_minutes: int = 20
    refresh_days: int = 30
    max_request_bytes: int = 8 * 1024 * 1024
    max_file_bytes: int = 2 * 1024 * 1024 * 1024
    chunk_bytes: int = 4 * 1024 * 1024
    # Empty for self-hosting; official deployment sets an explicit account allowlist.
    file_sync_allowed_emails: str = ''
    cloud_file_transfer_enabled: bool = False
    allow_password_auth: bool = True
    device_enrollment_enabled: bool = True
    smtp_config_file: Path = Path('private/smtp.json')
    # Independent of client accounts; blank disables the internal statistics UI.
    analytics_admin_username: str = Field(default='admin', min_length=1, max_length=80)
    analytics_admin_password: SecretStr | None = None
    release_directory: Path = Path('../web/public/downloads')

    @model_validator(mode='after')
    def production_secret(self):
        if self.analytics_admin_password:
            value = self.analytics_admin_password.get_secret_value()
            if value and len(value) < 16:
                raise ValueError('Analytics admin password must contain at least 16 characters')
        if self.app_env == 'production' and self.jwt_private_secret.startswith(('development', 'CHANGE_')):
            raise ValueError('Production requires a random JWT secret')
        return self
