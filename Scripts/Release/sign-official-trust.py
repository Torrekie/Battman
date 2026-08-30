#!/usr/bin/env python3
"""Sign exact official TrustMetadata.json bytes with one existing root key.

The command never generates keys and refuses to overwrite an existing root
signature. Run it only in the corresponding offline root-holder environment.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import plistlib
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.hashes import SHA256

from release_common import ReleaseError


def _regular_file(path: Path, label: str) -> Path:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink():
        raise ReleaseError(f"{label} must be a real regular file: {lexical}")
    return lexical


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plugin_trust", type=Path)
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--password-file", type=Path)
    arguments = parser.parse_args()

    trust = arguments.plugin_trust.expanduser().absolute()
    if not trust.is_dir() or trust.is_symlink():
        raise ReleaseError("PluginTrust must be a real directory")
    policy_path = _regular_file(trust / "RootPolicy.plist", "RootPolicy.plist")
    metadata_path = _regular_file(trust / "TrustMetadata.json", "TrustMetadata.json")
    signatures = trust / "TrustMetadata.signatures"
    if not signatures.is_dir() or signatures.is_symlink():
        raise ReleaseError("TrustMetadata.signatures must be a real directory")

    private_path = _regular_file(arguments.private_key, "root private key")
    password = None
    if arguments.password_file:
        password = _regular_file(arguments.password_file, "password file").read_bytes().rstrip(b"\r\n")
        if not password:
            raise ReleaseError("password file must not be empty")
    key = serialization.load_pem_private_key(private_path.read_bytes(), password=password)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ReleaseError("root private key must use ECDSA P-256")
    raw = key.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    identifier = hashlib.sha256(raw).hexdigest()

    try:
        policy = plistlib.loads(policy_path.read_bytes())
    except plistlib.InvalidFileException as error:
        raise ReleaseError("RootPolicy.plist is malformed") from error
    root_records = policy.get("rootPublicKeys") if isinstance(policy, dict) else None
    if not isinstance(root_records, list):
        raise ReleaseError("RootPolicy.plist has no rootPublicKeys array")
    matching = [record for record in root_records if isinstance(record, dict) and record.get("keyIdentifier") == identifier]
    if len(matching) != 1 or matching[0].get("publicKeyX963Base64") != base64.b64encode(raw).decode("ascii"):
        raise ReleaseError("the supplied private key is not one of the exact public roots")

    output = signatures / f"{identifier}.sig"
    if output.exists() or output.is_symlink():
        raise ReleaseError(f"root signature already exists: {output.name}")
    metadata = metadata_path.read_bytes()
    signature = key.sign(metadata, ec.ECDSA(SHA256(), deterministic_signing=True))
    key.public_key().verify(signature, metadata, ec.ECDSA(SHA256()))
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{identifier}.", dir=signatures)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(signature)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, output)
    except Exception:
        Path(temporary_name).unlink(missing_ok=True)
        raise
    print(identifier)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
