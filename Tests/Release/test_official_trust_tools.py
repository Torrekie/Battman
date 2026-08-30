#!/usr/bin/env python3
"""Portable official-trust validation and delegation-scope regression tests."""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.hashes import SHA256


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/Release"))
sys.path.insert(0, str(ROOT / "PluginSDK/Tools/Package"))

from official_trust import require_official_plugins, validate_official_trust  # noqa: E402
from release_common import ReleaseError  # noqa: E402


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (OSError, ReleaseError, ValueError):
        return
    raise AssertionError(f"expected hard failure: {label}")


def key() -> tuple[ec.EllipticCurvePrivateKey, bytes, str]:
    private = ec.generate_private_key(ec.SECP256R1())
    raw = private.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    return private, raw, hashlib.sha256(raw).hexdigest()


def trust_fixture(root: Path, root_private: ec.EllipticCurvePrivateKey,
                  root_raw: bytes, root_identifier: str,
                  publisher_raw: bytes, publisher_identifier: str) -> bytes:
    signatures = root / "TrustMetadata.signatures"
    signatures.mkdir(parents=True, mode=0o755)
    policy = {
        "schemaVersion": 1,
        "signatureThreshold": 1,
        "rootPublicKeys": [{
            "keyIdentifier": root_identifier,
            "publicKeyX963Base64": base64.b64encode(root_raw).decode(),
        }],
    }
    (root / "RootPolicy.plist").write_bytes(plistlib.dumps(policy, sort_keys=True))
    metadata = {
        "schemaVersion": 1,
        "sequence": 4,
        "generatedAtUnixSeconds": 123,
        "officialPublishers": [{
            "keyIdentifier": publisher_identifier,
            "publicKeyX963Base64": base64.b64encode(publisher_raw).decode(),
            "pluginIdentifiers": ["com.example.battman.official"],
            "extensionPointIdentifiers": ["com.torrekie.battman.analytics.card.v1"],
        }],
        "revokedKeyIdentifiers": [],
    }
    metadata_data = (json.dumps(metadata, sort_keys=True, separators=(",", ":")) + "\n").encode()
    (root / "TrustMetadata.json").write_bytes(metadata_data)
    signature = root_private.sign(metadata_data, ec.ECDSA(SHA256(), deterministic_signing=True))
    (signatures / f"{root_identifier}.sig").write_bytes(signature)
    for path in root.rglob("*"):
        path.chmod(0o755 if path.is_dir() else 0o644)
    return metadata_data


def package_fixture(package: Path, publisher_identifier: str,
                    extension_point: str = "com.torrekie.battman.analytics.card.v1") -> None:
    package.mkdir(mode=0o755)
    manifest = {
        "pluginIdentifier": "com.example.battman.official",
        "publisher": {"primaryKeyIdentifier": publisher_identifier},
        "extensionPoints": [{"identifier": extension_point, "interfaceVersion": 1}],
    }
    (package / "Manifest.json").write_text(
        json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8"
    )
    (package / "Manifest.json").chmod(0o644)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="battman-official-trust-tools-") as raw:
        temporary = Path(raw)
        root_private, root_raw, root_identifier = key()
        _, publisher_raw, publisher_identifier = key()
        trust_root = temporary / "PluginTrust"
        metadata_data = trust_fixture(trust_root, root_private, root_raw, root_identifier,
                                      publisher_raw, publisher_identifier)
        result = validate_official_trust(trust_root)
        assert result["sequence"] == 4
        assert result["verifiedRootKeyIdentifiers"] == [root_identifier]
        assert result["metadataSHA256"] == hashlib.sha256(metadata_data).hexdigest()

        package = temporary / "Official.battman"
        package_fixture(package, publisher_identifier)
        require_official_plugins([package], result)

        unrelated = temporary / "Unrelated.battman"
        package_fixture(unrelated, publisher_identifier, "com.example.unrelated.v1")
        expect_failure(lambda: require_official_plugins([unrelated], result), "delegation escape")
        expect_failure(lambda: require_official_plugins([], result), "empty official package set")

        tampered = temporary / "TamperedTrust"
        shutil.copytree(trust_root, tampered)
        (tampered / "TrustMetadata.json").write_bytes(metadata_data + b" ")
        expect_failure(lambda: validate_official_trust(tampered), "tampered metadata")

        noncanonical = temporary / "NoncanonicalSignatureTrust"
        shutil.copytree(trust_root, noncanonical)
        signature = noncanonical / "TrustMetadata.signatures" / f"{root_identifier}.sig"
        signature.write_bytes(b"\x30\x07\x02\x02\x00\x01\x02\x01\x01")
        expect_failure(lambda: validate_official_trust(noncanonical), "noncanonical root signature")

        unknown = temporary / "UnknownSignatureTrust"
        shutil.copytree(trust_root, unknown)
        signature = unknown / "TrustMetadata.signatures" / f"{root_identifier}.sig"
        signature.rename(signature.with_name("f" * 64 + ".sig"))
        expect_failure(lambda: validate_official_trust(unknown), "unknown signature key")

        linked = temporary / "LinkedTrust"
        shutil.copytree(trust_root, linked)
        (linked / "TrustMetadata.json").unlink()
        os.symlink(trust_root / "TrustMetadata.json", linked / "TrustMetadata.json")
        expect_failure(lambda: validate_official_trust(linked), "trust resource symlink")

        root_link = temporary / "PluginTrustLink"
        root_link.symlink_to(trust_root, target_is_directory=True)
        expect_failure(lambda: validate_official_trust(root_link), "top-level trust symlink")
        package_link = temporary / "OfficialLink.battman"
        package_link.symlink_to(package, target_is_directory=True)
        expect_failure(lambda: require_official_plugins([package_link], result), "top-level package symlink")

    print("Portable official-trust signature and delegation-scope tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
