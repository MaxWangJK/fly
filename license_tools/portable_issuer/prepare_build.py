"""Build-time only. No secret material is printed or copied to public outputs."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import struct
from zipfile import ZipFile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def prepare(package: Path, target: Path) -> None:
    root = Path(__file__).resolve().parents[2]
    spec = json.loads(Path(__file__).with_name('dependency.json').read_text())
    digest = base64.b64encode(hashlib.sha512(package.read_bytes()).digest()).decode()
    if digest != spec['sha512base64']:
        raise ValueError('Dependency checksum mismatch; use the pinned official package.')
    private = serialization.load_pem_private_key((root / 'license_tools/private/issuer.pem').read_bytes(), None)
    if not isinstance(private, Ed25519PrivateKey):
        raise ValueError('The existing issuer identity must use Ed25519.')
    public = base64.urlsafe_b64encode(private.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode().rstrip('=')
    if public != (root / 'license_tools/public_key.txt').read_text().strip():
        raise ValueError('Original issuer and Fly public key do not match; do not regenerate them.')
    target.mkdir(parents=True, exist_ok=True)
    with ZipFile(package) as archive:
        assembly = archive.read(spec['assembly'])
        (target / 'BouncyCastle.Cryptography.dll').write_bytes(assembly)
        (target / 'crypto.gz').write_bytes(gzip.compress(assembly, compresslevel=9, mtime=0))
        notice = archive.read('LICENSE.md')
        (target / 'THIRD-PARTY-NOTICES.txt').write_bytes(notice)
    pixels = []
    for y in range(64):
        row = []
        for x in range(64):
            corner_x, corner_y = max(11 - x, x - 52, 0), max(11 - y, y - 52, 0)
            inside = corner_x * corner_x + corner_y * corner_y <= 121
            letter = (20 <= x < 27 and 16 <= y < 49) or (20 <= x < 46 and 16 <= y < 23) or (20 <= x < 41 and 30 <= y < 37)
            row.append(bytes((255, 255, 255, 255)) if letter else bytes((121, 109, 20, 255 if inside else 0)))
        pixels.append(b''.join(row))
    bitmap = b''.join(reversed(pixels))
    dib = struct.pack('<IiiHHIIiiII', 40, 64, 128, 1, 32, 0, len(bitmap), 0, 0, 0, 0) + bitmap + bytes(64 * 8)
    icon = struct.pack('<HHH', 0, 1, 1) + struct.pack('<BBBBHHII', 64, 64, 0, 0, 1, 32, len(dib), 22) + dib
    (target / 'issuer.ico').write_bytes(icon)
    print('Pinned dependency verified; original signing identity matches Fly; build resources ready.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('target', type=Path)
    args = parser.parse_args()
    prepare(args.package, args.target)
