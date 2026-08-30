#!/usr/bin/env python3
"""Create or verify a deterministic P-256 signature over exact checksum bytes."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from release_common import ReleaseError, require_new_output, source_date_epoch, write_normalized


def _load_public(path: Path) -> ec.EllipticCurvePublicKey:
    lexical = path.expanduser().absolute()
    entry = lexical.lstat()
    if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1 or entry.st_size > 16 * 1024:
        raise ReleaseError("checksum verification key must be one bounded regular file")
    key = serialization.load_pem_public_key(lexical.read_bytes())
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ReleaseError("checksum verification key must be P-256")
    return key


def _key_identifier(key: ec.EllipticCurvePublicKey) -> str:
    raw = key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    return hashlib.sha256(raw).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--private-key", type=Path)
    modes.add_argument("--public-key", type=Path)
    parser.add_argument("--checksums", required=True, type=Path)
    parser.add_argument("--signature", required=True, type=Path)
    parser.add_argument("--password-file", type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()

    checksums = arguments.checksums.expanduser().resolve()
    checksums_entry = checksums.lstat()
    if not stat.S_ISREG(checksums_entry.st_mode) or checksums_entry.st_nlink != 1 or \
            checksums_entry.st_size > 2 * 1024 * 1024:
        raise ReleaseError("checksums input must be one bounded regular file")
    data = checksums.read_bytes()
    if arguments.private_key:
        epoch = source_date_epoch(arguments.source_date_epoch)
        signature_path = require_new_output(arguments.signature, ".sig")
        if signature_path.parent != checksums.parent:
            raise ReleaseError("checksum signature must share the release directory")
        private_path = arguments.private_key.expanduser().absolute()
        private_entry = private_path.lstat()
        if not stat.S_ISREG(private_entry.st_mode) or private_entry.st_nlink != 1 or \
                private_entry.st_size > 64 * 1024:
            raise ReleaseError("checksum private key must be one bounded regular file")
        password = None
        if arguments.password_file:
            password_path = arguments.password_file.expanduser().absolute()
            password_entry = password_path.lstat()
            if not stat.S_ISREG(password_entry.st_mode) or password_entry.st_nlink != 1 or \
                    password_entry.st_size > 4096:
                raise ReleaseError("checksum password file must be one bounded regular file")
            password = password_path.read_bytes().rstrip(b"\r\n")
            if not password:
                raise ReleaseError("checksum password file must not be empty")
        private_key = serialization.load_pem_private_key(
            private_path.read_bytes(), password=password
        )
        if not isinstance(private_key, ec.EllipticCurvePrivateKey) or not isinstance(private_key.curve, ec.SECP256R1):
            raise ReleaseError("checksum signing key must use P-256")
        signature = private_key.sign(data, ec.ECDSA(hashes.SHA256(), deterministic_signing=True))
        write_normalized(signature_path, signature, epoch)
        print(_key_identifier(private_key.public_key()))
        print(signature_path)
        return 0

    signature_path = arguments.signature.expanduser().resolve()
    signature_entry = signature_path.lstat()
    if not stat.S_ISREG(signature_entry.st_mode) or signature_entry.st_nlink != 1 or \
            not 1 <= signature_entry.st_size <= 1024:
        raise ReleaseError("signature input must be one bounded regular file")
    public_key = _load_public(arguments.public_key)
    try:
        public_key.verify(signature_path.read_bytes(), data, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature as error:
        raise ReleaseError("checksum signature verification failed") from error
    print(_key_identifier(public_key))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
