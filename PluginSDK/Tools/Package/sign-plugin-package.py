#!/usr/bin/env python3
"""Sign exact Manifest.json bytes with an existing P-256 private key."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.hashes import SHA256

from battman_plugin_format import (
    PluginFormatError,
    load_strict_json,
    signature_paths,
    validate_author_metadata,
    validate_display_name,
)


def _regular_file(path: Path, label: str) -> Path:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink():
        raise PluginFormatError(f"{label} must be a real regular file")
    return lexical


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--password-file", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    package = arguments.package.expanduser().absolute()
    if package.suffix != ".battman" or not package.is_dir() or package.is_symlink():
        raise PluginFormatError("package must be a .battman directory")
    manifest_path = _regular_file(package / "Manifest.json", "Manifest.json")
    private_key_path = _regular_file(arguments.private_key, "private key")
    password = None
    if arguments.password_file:
        password = _regular_file(arguments.password_file, "password file").read_bytes().rstrip(b"\r\n")
        if not password:
            raise PluginFormatError("password file must not be empty")
    key = serialization.load_pem_private_key(private_key_path.read_bytes(), password=password)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise PluginFormatError("private key must use ECDSA P-256")
    public = key.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    import hashlib

    identifier = hashlib.sha256(public).hexdigest()
    manifest_data = manifest_path.read_bytes()
    manifest = load_strict_json(manifest_data)
    if not isinstance(manifest, dict):
        raise PluginFormatError("manifest must be an object")
    validate_display_name(manifest)
    validate_author_metadata(manifest)
    declared = dict(signature_paths(manifest))
    if identifier not in declared:
        raise PluginFormatError("private-key fingerprint is not declared by the manifest")
    signature = key.sign(manifest_data, ec.ECDSA(SHA256(), deterministic_signing=True))
    if len(signature) > 256:
        raise PluginFormatError("generated signature exceeds package limit")
    signature_path = package / declared[identifier]
    if signature_path.exists() or signature_path.is_symlink():
        raise PluginFormatError("publisher signature already exists")
    if signature_path.parent.exists():
        if not signature_path.parent.is_dir() or signature_path.parent.is_symlink():
            raise PluginFormatError("signature directory must be a real directory")
    else:
        signature_path.parent.mkdir(mode=0o755)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{identifier}.", dir=signature_path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(signature)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, signature_path)
    except Exception:
        Path(temporary_name).unlink(missing_ok=True)
        raise
    print(identifier)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, PluginFormatError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
