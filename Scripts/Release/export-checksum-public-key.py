#!/usr/bin/env python3
"""Export an unencrypted ephemeral engineering checksum key's public half.

Production checksum keys remain encrypted at rest; export their public half on
the owner-controlled key station with the reviewed key tool instead of this
helper.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from release_common import ReleaseError, require_new_output, source_date_epoch, write_normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-key-id")
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    output = require_new_output(arguments.output, ".pub")
    private_path = arguments.private_key.expanduser().resolve()
    if not private_path.is_file() or private_path.is_symlink():
        raise ReleaseError("checksum private key must be an existing regular file")
    key = serialization.load_pem_private_key(private_path.read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ReleaseError("engineering checksum key must be an unencrypted P-256 private key")
    public = key.public_key()
    raw = public.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    identifier = hashlib.sha256(raw).hexdigest()
    if arguments.expected_key_id and arguments.expected_key_id != identifier:
        raise ReleaseError("checksum signing key does not match the owner-approved public-key fingerprint")
    pem = public.public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    write_normalized(output, pem, epoch)
    print(identifier)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
