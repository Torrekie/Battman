#!/usr/bin/env python3
"""Validate and fingerprint an existing public P-256 checksum key."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from release_common import ReleaseError


def checksum_public_key_identifier(path: Path) -> str:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink() or lexical.stat().st_size > 16 * 1024:
        raise ReleaseError("checksum public key must be one bounded regular file")
    key = serialization.load_pem_public_key(lexical.read_bytes())
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise ReleaseError("checksum public key must use P-256")
    raw = key.public_bytes(
        serialization.Encoding.X962,
        serialization.PublicFormat.UncompressedPoint,
    )
    return hashlib.sha256(raw).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("public_key", type=Path)
    parser.add_argument("--expected-key-id")
    arguments = parser.parse_args()
    identifier = checksum_public_key_identifier(arguments.public_key)
    if arguments.expected_key_id and arguments.expected_key_id != identifier:
        raise ReleaseError(
            "checksum public key does not match the owner-approved fingerprint"
        )
    print(identifier)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
