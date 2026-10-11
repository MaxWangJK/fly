from pathlib import Path
from typing import Protocol
import re


class BlobStorage(Protocol):
    def blob(self, user_id: str, sha256: str) -> Path: ...
    def partial(self, user_id: str, session_id: str) -> Path: ...


class LocalDiskBlobStorage:
    def __init__(self, root: Path):
        self.root = root.resolve()

    def _path(self, user_id, name):
        if not re.fullmatch(r'[a-f0-9-]{36}', user_id) or not re.fullmatch(r'(?:[a-f0-9]{64}|[a-f0-9-]{36}\.part)', name):
            raise ValueError('Invalid storage identity')
        path = (self.root / user_id / name).resolve()
        if not path.is_relative_to(self.root):
            raise ValueError('Invalid storage path')
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def blob(self, user_id, sha256):
        if not re.fullmatch(r'[a-f0-9]{64}', sha256):
            raise ValueError('Invalid hash')
        return self._path(user_id, sha256)

    def partial(self, user_id, session_id):
        return self._path(user_id, session_id + '.part')
