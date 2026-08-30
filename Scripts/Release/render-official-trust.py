#!/usr/bin/env python3
"""Render canonical public official-trust inputs from existing public keys.

This tool reads public keys only. It never generates a key, reads a private
key, or signs metadata.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from release_common import ReleaseError, require_identifier


KEY_IDENTIFIER = re.compile(r"^[0-9a-f]{64}$")
MAX_JSON_INTEGER = 9_007_199_254_740_991


def _public_point(path: Path) -> tuple[str, bytes]:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink():
        raise ReleaseError(f"public key must be a real regular file: {lexical}")
    data = lexical.read_bytes()
    if len(data) == 65 and data[0] == 4:
        raw = data
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)
    else:
        key = serialization.load_pem_public_key(data)
        if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
            raise ReleaseError(f"public key is not P-256: {lexical}")
        raw = key.public_bytes(
            serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint,
        )
    return hashlib.sha256(raw).hexdigest(), raw


def _bounded_integer(value: int, minimum: int, label: str) -> int:
    if value < minimum or value > MAX_JSON_INTEGER:
        raise ReleaseError(f"{label} is outside the supported integer range")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-public-key", action="append", required=True, type=Path)
    parser.add_argument("--publisher-public-key", required=True, type=Path)
    parser.add_argument("--plugin-identifier", action="append", required=True)
    parser.add_argument("--extension-point", action="append", required=True)
    parser.add_argument("--threshold", required=True, type=int)
    parser.add_argument("--sequence", required=True, type=int)
    parser.add_argument("--generated-at-unix-seconds", required=True, type=int)
    parser.add_argument("--revoked-key-identifier", action="append", default=[])
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    if len(arguments.root_public_key) != 3 or arguments.threshold != 2:
        raise ReleaseError("Battman 1.1.0 official trust requires exactly a 2-of-3 root policy")
    output = arguments.output.expanduser().absolute()
    if output.exists() or output.is_symlink() or not output.parent.is_dir() or output.parent.is_symlink():
        raise ReleaseError("output must be a new directory under a real existing parent")

    root_records = []
    seen_roots: set[str] = set()
    for path in arguments.root_public_key:
        identifier, raw = _public_point(path)
        if identifier in seen_roots:
            raise ReleaseError(f"duplicate root public key: {identifier}")
        seen_roots.add(identifier)
        root_records.append({
            "keyIdentifier": identifier,
            "publicKeyX963Base64": base64.b64encode(raw).decode("ascii"),
        })
    root_records.sort(key=lambda value: value["keyIdentifier"].encode("utf-8"))

    publisher_identifier, publisher_raw = _public_point(arguments.publisher_public_key)
    plugin_identifiers = sorted(
        {require_identifier(value, "official plug-in identifier") for value in arguments.plugin_identifier},
        key=lambda value: value.encode("utf-8"),
    )
    extension_points = sorted(
        {require_identifier(value, "official extension-point identifier") for value in arguments.extension_point},
        key=lambda value: value.encode("utf-8"),
    )
    if len(plugin_identifiers) != len(arguments.plugin_identifier) or len(extension_points) != len(arguments.extension_point):
        raise ReleaseError("official trust scopes must not contain duplicate identifiers")
    revoked = sorted(set(arguments.revoked_key_identifier), key=lambda value: value.encode("utf-8"))
    if len(revoked) != len(arguments.revoked_key_identifier) or any(
        not KEY_IDENTIFIER.fullmatch(identifier) for identifier in revoked
    ):
        raise ReleaseError("revoked key identifiers must be unique lowercase SHA-256 fingerprints")
    if publisher_identifier in revoked:
        raise ReleaseError("one metadata version cannot delegate and revoke the official publisher key")

    root_policy = {
        "schemaVersion": 1,
        "signatureThreshold": arguments.threshold,
        "rootPublicKeys": root_records,
    }
    metadata = {
        "schemaVersion": 1,
        "sequence": _bounded_integer(arguments.sequence, 1, "metadata sequence"),
        "generatedAtUnixSeconds": _bounded_integer(
            arguments.generated_at_unix_seconds, 0, "metadata generation time"
        ),
        "officialPublishers": [{
            "keyIdentifier": publisher_identifier,
            "publicKeyX963Base64": base64.b64encode(publisher_raw).decode("ascii"),
            "pluginIdentifiers": plugin_identifiers,
            "extensionPointIdentifiers": extension_points,
        }],
        "revokedKeyIdentifiers": revoked,
    }

    try:
        output.mkdir(mode=0o755)
        signatures = output / "TrustMetadata.signatures"
        signatures.mkdir(mode=0o755)
        policy_path = output / "RootPolicy.plist"
        policy_path.write_bytes(plistlib.dumps(root_policy, fmt=plistlib.FMT_XML, sort_keys=True))
        metadata_path = output / "TrustMetadata.json"
        metadata_path.write_bytes(
            (json.dumps(metadata, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        )
        for path in (policy_path, metadata_path):
            os.chmod(path, 0o644)
    except Exception:
        import shutil
        shutil.rmtree(output, ignore_errors=True)
        raise
    print(output)
    print(f"rootKeyIdentifiers={','.join(record['keyIdentifier'] for record in root_records)}")
    print(f"publisherKeyIdentifier={publisher_identifier}")
    print("signaturesRequired=2")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
