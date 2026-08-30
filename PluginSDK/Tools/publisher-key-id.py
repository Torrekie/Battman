#!/usr/bin/env python3
"""Inspect a P-256 public key without reading or generating private keys."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("public_key", type=Path)
    parser.add_argument(
        "--raw-output",
        type=Path,
        help="write the 65-byte X9.63 public point used by .battman packages",
    )
    arguments = parser.parse_args()
    data = arguments.public_key.read_bytes()
    if len(data) == 65 and data[0] == 4:
        raw = data
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
    else:
        key = serialization.load_pem_public_key(data)
        if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
            raise ValueError("public key must use ECDSA P-256")
        raw = key.public_bytes(
            serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint,
        )
    identifier = hashlib.sha256(raw).hexdigest()
    if arguments.raw_output:
        output = arguments.raw_output.resolve()
        if output.exists() or not output.parent.is_dir():
            raise ValueError("raw output must not exist and its parent directory must exist")
        output.write_bytes(raw)
    print(identifier)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
