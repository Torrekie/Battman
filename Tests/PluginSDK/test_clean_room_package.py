#!/usr/bin/env python3
"""Package the copied SDK example using only copied SDK tools."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(arguments, text=True, capture_output=True, env=environment)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(arguments)}\n{result.stderr}"
        )
    return result


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: test_clean_room_package.py SDK_ROOT BUNDLE TEMP_ROOT")
    sdk = Path(sys.argv[1]).resolve()
    bundle = Path(sys.argv[2]).resolve()
    root = Path(sys.argv[3]).resolve()
    tools = sdk / "Tools" / "Package"

    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()
    raw_public = public_key.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    key_identifier = hashlib.sha256(raw_public).hexdigest()
    private_path = root / "ephemeral-sdk-test-private.pem"
    public_path = root / "ephemeral-sdk-test-public.pem"
    private_path.write_bytes(
        private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    os.chmod(private_path, 0o600)
    public_path.write_bytes(
        public_key.public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )

    raw_public_path = root / "ephemeral-sdk-test-public.p256"
    inspected_identifier = run(
        sys.executable,
        str(sdk / "Tools" / "publisher-key-id.py"),
        str(public_path),
        "--raw-output",
        str(raw_public_path),
    ).stdout.strip()
    if inspected_identifier != key_identifier or raw_public_path.read_bytes() != raw_public:
        raise AssertionError("SDK public-key inspection changed the P-256 identity")

    template = root / "ExampleManifestTemplate.json"
    run(
        sys.executable,
        str(sdk / "Tools" / "render-example-manifest.py"),
        "--publisher-key-id",
        key_identifier,
        "--output",
        str(template),
    )
    first = root / "First.battman"
    second = root / "Second.battman"
    for output in (first, second):
        run(
            sys.executable,
            str(tools / "build-plugin-package.py"),
            "--manifest-template",
            str(template),
            "--payload",
            str(bundle),
            "--publisher-public-key",
            str(raw_public_path),
            "--output",
            str(output),
        )
    if (first / "Manifest.json").read_bytes() != (second / "Manifest.json").read_bytes():
        raise AssertionError("clean-room package manifest was not deterministic")
    if (first / "Info.plist").read_bytes() != (second / "Info.plist").read_bytes():
        raise AssertionError("clean-room outer package plist was not deterministic")

    signed_identifier = run(
        sys.executable,
        str(tools / "sign-plugin-package.py"),
        str(first),
        "--private-key",
        str(private_path),
    ).stdout.strip()
    if signed_identifier != key_identifier:
        raise AssertionError("SDK signer used an unexpected publisher key identifier")
    report = json.loads(
        run(
            sys.executable,
            str(tools / "verify-plugin-package.py"),
            str(first),
        ).stdout
    )
    if report["pluginIdentifier"] != "com.torrekie.battman.example.analytics":
        raise AssertionError("clean-room package identity changed")
    if report["verifiedPublisherKeys"] != [f"{key_identifier}:package"]:
        raise AssertionError("clean-room package-contained publisher signature was not verified")
    if report["nativeVerificationRequired"] is not True:
        raise AssertionError("portable verifier overstated its activation scope")
    print("Clean-room deterministic package, existing-key signing, and offline verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
