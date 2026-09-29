"""Internal-only Ed25519 issuer. Never distribute this directory to customers."""
import argparse
import base64
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re
import secrets

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = Path(__file__).resolve().parent
PRIVATE = ROOT / "private" / "issuer.pem"
PUBLIC = ROOT / "public_key.txt"


def encoded(value):
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--init", action="store_true", help="Create issuer key once; never overwrites")
    parser.add_argument("--machine")
    parser.add_argument("--days", type=int)
    args = parser.parse_args()
    if args.init:
        if args.machine or args.days is not None:
            parser.error("Use --init separately from issuing a license")
        if PRIVATE.exists() or PUBLIC.exists():
            parser.error("Key already exists. Back up your existing issuer; no key was overwritten.")
        PRIVATE.parent.mkdir(parents=True, exist_ok=True)
        key = Ed25519PrivateKey.generate()
        pem = key.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        descriptor = os.open(PRIVATE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(pem)
        public = encoded(key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw))
        with PUBLIC.open("x", encoding="ascii") as stream:
            stream.write(public + "\n")
        print("Issuer created. Restrict the private directory ACL and back it up offline.")
        print("Public key: " + public)
        return
    machine = (args.machine or "").strip().upper()
    if not re.fullmatch(r"[0-9A-F]{64}", machine):
        parser.error("--machine must be the complete 64-character Fly machine code")
    if args.days is None or not 1 <= args.days <= 36500:
        parser.error("--days must be a positive integer, at most 36500")
    if not PRIVATE.exists():
        parser.error("Issuer not initialized. Run --init once, then build with its public key.")
    key = serialization.load_pem_private_key(PRIVATE.read_bytes(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        parser.error("Issuer must be an Ed25519 key")
    now = datetime.now(timezone.utc)
    payload = json.dumps({"machineCode": machine,
        "issuedAt": now.isoformat().replace("+00:00", "Z"),
        "expiresAt": (now + timedelta(days=args.days)).isoformat().replace("+00:00", "Z"),
        "licenseVersion": 1, "nonce": secrets.token_hex(16)},
        separators=(",", ":"), sort_keys=True).encode("utf-8")
    print(encoded(payload) + "." + encoded(key.sign(payload)))


if __name__ == "__main__":
    main()
