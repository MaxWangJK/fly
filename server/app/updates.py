"""Public release lookup/download. No device code or client account is accepted."""
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re
from urllib.parse import quote

from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import FileResponse

_filename = re.compile(
    r'Fly-(?:Setup-)?(?P<version>\d{1,5}\.\d{1,5}(?:\.\d{1,5})?)'
    r'(?:-build(?P<build>\d{1,9}))?(?:-(?P<platform>windows|android))?\.(?P<ext>exe|apk)\Z',
    re.IGNORECASE | re.ASCII,
)


@dataclass(frozen=True)
class Release:
    path: Path
    version: tuple[int, int, int]
    build: int
    platform: str


class ReleaseCatalog:
    def __init__(self, directory):
        self.directory = Path(directory)
        self._hashes = {}

    def release(self, path):
        match = _filename.fullmatch(path.name)
        if not match or path.is_symlink() or not path.is_file() or path.stat().st_size < 1:
            return None
        if path.resolve().parent != self.directory.resolve():
            return None
        platform = 'windows' if match['ext'].lower() == 'exe' else 'android'
        if match['platform'] and match['platform'].lower() != platform:
            return None
        parts = [int(part) for part in match['version'].split('.')]
        if len(parts) == 2:
            parts.append(0)
        return Release(path, tuple(parts), int(match['build'] or 0), platform)

    def latest(self, platform):
        if not self.directory.exists():
            return None
        candidates = [release for path in self.directory.iterdir()
                      if (release := self.release(path)) and release.platform == platform]
        return max(candidates, key=lambda r: (r.version, r.build, r.path.name), default=None)

    def metadata(self, release):
        path = release.path
        before = path.stat()
        key = (str(path), before.st_size, before.st_mtime_ns)
        digest = self._hashes.get(key)
        if digest is None:
            with path.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            after = path.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise OSError('Release upload is still changing')
            if len(self._hashes) >= 32:
                self._hashes.clear()
            self._hashes[key] = digest
        return {'version': '.'.join(map(str, release.version)), 'build': release.build,
                'fileName': path.name, 'size': before.st_size, 'sha256': digest,
                'downloadPath': '/api/updates/download/' + quote(path.name, safe='')}


def create_update_router(settings):
    router = APIRouter()
    catalog = ReleaseCatalog(settings.release_directory)

    @router.get('/api/updates/latest/{platform}')
    def latest(platform: str, response: Response):
        if platform not in ('windows', 'android'):
            raise HTTPException(400, 'Unsupported update platform')
        response.headers['Cache-Control'] = 'no-store'
        try:
            release = catalog.latest(platform)
            return {'latest': catalog.metadata(release) if release else None}
        except OSError:
            raise HTTPException(503, 'Release information is temporarily unavailable') from None

    @router.get('/api/updates/download/{filename}', name='download_fly_release')
    def download(filename: str):
        if not _filename.fullmatch(filename):
            raise HTTPException(404, 'Release not found')
        release = catalog.release(catalog.directory / filename)
        if release is None:
            raise HTTPException(404, 'Release not found')
        return FileResponse(release.path, filename=release.path.name,
            media_type='application/vnd.android.package-archive' if release.platform == 'android'
                       else 'application/octet-stream',
            headers={'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff'})

    return router
