from pathlib import Path
from pydantic import Field, model_validator
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

    @model_validator(mode='after')
    def production_secret(self):
        if self.app_env == 'production' and self.jwt_private_secret.startswith(('development', 'CHANGE_')):
            raise ValueError('Production requires a random JWT secret')
        return self
