#!/usr/bin/env python3
"""Portable offline envelope/hash/publisher-signature verifier.

The app's native verifier remains authoritative for Mach-O, platform signature,
host ABI, rollback, revocation, and activation decisions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.hashes import SHA256

from battman_plugin_format import (
    MAX_SIGNATURE_BYTES,
    PluginFormatError,
    load_strict_json,
    package_digest,
    signature_paths,
    validate_author_metadata,
    validate_display_name,
    verify_exact_package_files,
    verify_inventory,
    verify_outer_info,
    verify_payload_structure,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--public-key", action="append", default=[], type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    package = arguments.package.expanduser().absolute()
    if package.suffix != ".battman" or not package.is_dir() or package.is_symlink():
        raise PluginFormatError("package must be a .battman directory")
    manifest_data = (package / "Manifest.json").read_bytes()
    manifest = load_strict_json(manifest_data)
    if not isinstance(manifest, dict):
        raise PluginFormatError("manifest must be an object")
    validate_display_name(manifest)
    validate_author_metadata(manifest)
    verify_inventory(package, manifest)
    verify_exact_package_files(package, manifest)
    verify_payload_structure(package, manifest)
    verify_outer_info(package, manifest)

    external: dict[str, bytes] = {}
    for path in arguments.public_key:
        key = serialization.load_pem_public_key(path.read_bytes())
        if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
            raise PluginFormatError(f"public key is not P-256: {path}")
        raw = key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
        external[hashlib.sha256(raw).hexdigest()] = raw

    verified: list[str] = []
    for identifier, signature_relative in signature_paths(manifest):
        raw_key = external.get(identifier)
        key_source = "external"
        if raw_key is None:
            included = package / "PublisherKeys" / f"{identifier}.p256"
            raw_key = included.read_bytes()
            key_source = "package"
        if len(raw_key) != 65 or raw_key[0] != 4 or hashlib.sha256(raw_key).hexdigest() != identifier:
            raise PluginFormatError(f"P-256 key fingerprint mismatch: {identifier}")
        signature = (package / signature_relative).read_bytes()
        if not signature or len(signature) > MAX_SIGNATURE_BYTES:
            raise PluginFormatError(f"invalid signature size: {signature_relative}")
        public_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw_key)
        try:
            public_key.verify(signature, manifest_data, ec.ECDSA(SHA256()))
        except InvalidSignature as exc:
            raise PluginFormatError(f"signature does not match exact Manifest.json bytes: {identifier}") from exc
        verified.append(f"{identifier}:{key_source}")

    output = {
        "pluginIdentifier": manifest.get("pluginIdentifier"),
        "packageSHA256": package_digest(package),
        "verifiedPublisherKeys": verified,
        "portableScope": "envelope-hash-publisher-signature",
        "nativeVerificationRequired": True,
    }
    print(json.dumps(output, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, PluginFormatError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
