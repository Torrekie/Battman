#!/usr/bin/env python3
"""Regression tests for public-only production-key ceremony evidence."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "Scripts/Release/validate-production-key-evidence.py"
ROLES = {
    "root-r1": "official-trust-root",
    "root-r2": "official-trust-root",
    "root-r3": "official-trust-root",
    "official-plugin-publisher": "official-plugin-publisher",
    "release-checksum": "release-checksum",
    "sdk-example-publisher": "sdk-example-publisher",
}
BACKUP_FINGERPRINTS = [
    "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
]
PRIVATE_KEY_ARTIFACT_SHA256 = "c" * 64
PRIVATE_KEY_ARTIFACT_SIZE = 399


def run(path: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(path), *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def write_record(root: Path, *, reviewed: bool) -> None:
    toolchain = {
        "backupAvailabilityPolicy": "live-pinned-hosts-required-for-backup-only",
        "backupHostFingerprints": BACKUP_FINGERPRINTS,
        "ceremonyScriptSHA256": "d" * 64,
        "cryptographyVersion": "49.0.0",
        "hostBuildVersion": "test-build",
        "hostProductVersion": "test-product",
        "networkPolicy": "trusted-private-lan-permitted",
        "opensslExecutableSHA256": "f" * 64,
        "opensslVersion": "OpenSSL test fixture",
        "pythonExecutableSHA256": "e" * 64,
        "pythonVersion": "3.14.6",
        "schemaVersion": 3,
        "targetAddressPolicy": "manual-private-ipv4-per-live-run",
    }
    toolchain_data = (json.dumps(toolchain, indent=2, sort_keys=True) + "\n").encode()
    (root / "toolchain.json").write_bytes(toolchain_data)
    roles = []
    for role, scope in ROLES.items():
        private = ec.generate_private_key(ec.SECP256R1())
        public = private.public_key()
        raw = public.public_bytes(
            serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint,
        )
        identifier = hashlib.sha256(raw).hexdigest()
        public_path = root / "keys" / f"{role}.public.pem"
        public_path.write_bytes(public.public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        ))
        challenge = (
            "Battman production-key recovery challenge\n"
            "ceremony=battman-1.1.0-production-keys-1\n"
            f"role={role}\n"
            f"keyIdentifier={identifier}\n"
            f"privateKeyArtifactSHA256={PRIVATE_KEY_ARTIFACT_SHA256}\n"
            f"privateKeyArtifactSize={PRIVATE_KEY_ARTIFACT_SIZE}\n"
        ).encode("ascii")
        challenge_path = root / "challenges" / f"{role}.challenge"
        signature_path = root / "challenges" / f"{role}.challenge.p256.sig"
        challenge_path.write_bytes(challenge)
        signature_path.write_bytes(private.sign(challenge, ec.ECDSA(hashes.SHA256())))
        roles.append({
            "backupCopies": 2,
            "backupFiles": [
                {
                    "artifactSHA256": PRIVATE_KEY_ARTIFACT_SHA256,
                    "artifactSize": PRIVATE_KEY_ARTIFACT_SIZE,
                    "hostIdentifier": host_identifier,
                    "remoteFile": f"{role}.private.pem",
                    "restoreTested": index == 0,
                    "storedAtUnixSeconds": 1700000050 + index * 20,
                    "verifiedAtUnixSeconds": 1700000060 + index * 20,
                }
                for index, host_identifier in enumerate(("backup-a", "backup-b"))
            ],
            "challengeFile": f"challenges/{role}.challenge",
            "challengeSignatureFile": f"challenges/{role}.challenge.p256.sig",
            "keyIdentifier": identifier,
            "privateKeyArtifactFormat": "PKCS8-PBES2-scrypt-AES-256-CBC",
            "privateKeyArtifactSHA256": PRIVATE_KEY_ARTIFACT_SHA256,
            "privateKeyArtifactSize": PRIVATE_KEY_ARTIFACT_SIZE,
            "publicKeyFile": f"keys/{role}.public.pem",
            "recoveryVerifiedAtUnixSeconds": 1700000100,
            "role": role,
            "rotationReviewDueUnixSeconds": 1731536100,
            "scope": scope,
        })
    value = {
        "backupHosts": [
            {
                "hostKeyFingerprint": fingerprint,
                "identifier": identifier,
                "offlineStorageConfirmed": reviewed,
            }
            for index, (identifier, fingerprint) in enumerate((
                ("backup-a", BACKUP_FINGERPRINTS[0]),
                ("backup-b", BACKUP_FINGERPRINTS[1]),
            ))
        ],
        "ceremonyIdentifier": "battman-1.1.0-production-keys-1",
        "codeFreezeCommit": "a" * 40 if reviewed else None,
        "generatedAtUnixSeconds": 1700000000,
        "operatorIdentifier": "test-operator",
        "reviewer": {
            "backupDigestsCompared": True,
            "challengesVerified": True,
            "fingerprintsCompared": True,
            "identifier": "independent-test-reviewer",
            "physicalSeparationConfirmed": True,
            "reviewedAtUnixSeconds": 1700000300,
        } if reviewed else None,
        "roles": roles,
        "schemaVersion": 3,
        "toolImageSHA256": hashlib.sha256(toolchain_data).hexdigest(),
        "toolVersion": "OpenSSL test fixture",
    }
    (root / "ceremony.json").write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def fixture(root: Path, *, reviewed: bool = False) -> Path:
    evidence = root / "ProductionKeyEvidence"
    (evidence / "keys").mkdir(parents=True)
    (evidence / "challenges").mkdir()
    write_record(evidence, reviewed=reviewed)
    return evidence


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="battman-production-key-evidence-") as raw:
        temporary = Path(raw)
        prepared = fixture(temporary / "prepared")
        result = run(prepared)
        assert result.returncode == 0, result.stderr
        report = json.loads(result.stdout)
        assert report["roleCount"] == 6 and report["reviewed"] is False
        assert report["backupHostCount"] == 2
        assert (
            report["backupAvailabilityPolicy"]
            == "live-pinned-hosts-required-for-backup-only"
        )
        assert report["networkPolicy"] == "trusted-private-lan-permitted"
        assert report["targetAddressPolicy"] == "manual-private-ipv4-per-live-run"
        unreviewed = run(prepared, "--require-reviewed")
        assert unreviewed.returncode == 2
        assert "post-freeze review" in unreviewed.stderr

        reviewed = fixture(temporary / "reviewed", reviewed=True)
        result = run(reviewed, "--require-reviewed")
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["reviewed"] is True

        tampered = temporary / "tampered"
        shutil.copytree(reviewed, tampered)
        challenge = tampered / "challenges/root-r1.challenge"
        challenge.write_bytes(challenge.read_bytes() + b"tampered\n")
        assert run(tampered, "--require-reviewed").returncode == 2

        mismatched_backup = temporary / "mismatched-backup"
        shutil.copytree(reviewed, mismatched_backup)
        record = json.loads((mismatched_backup / "ceremony.json").read_text())
        record["roles"][0]["backupFiles"][1]["artifactSHA256"] = "0" * 64
        (mismatched_backup / "ceremony.json").write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        assert run(mismatched_backup, "--require-reviewed").returncode == 2

        injected = temporary / "injected"
        shutil.copytree(reviewed, injected)
        (injected / "private.pem").write_text("forbidden extra\n", encoding="utf-8")
        assert run(injected, "--require-reviewed").returncode == 2

        unsupported_network = temporary / "unsupported-network"
        shutil.copytree(prepared, unsupported_network)
        toolchain_path = unsupported_network / "toolchain.json"
        toolchain = json.loads(toolchain_path.read_text(encoding="utf-8"))
        toolchain["networkPolicy"] = "unrecorded-network-policy"
        toolchain_data = (json.dumps(toolchain, indent=2, sort_keys=True) + "\n").encode()
        toolchain_path.write_bytes(toolchain_data)
        record_path = unsupported_network / "ceremony.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["toolImageSHA256"] = hashlib.sha256(toolchain_data).hexdigest()
        record_path.write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        rejected = run(unsupported_network)
        assert rejected.returncode == 2
        assert "networkPolicy" in rejected.stderr

        unsupported_availability = temporary / "unsupported-availability"
        shutil.copytree(prepared, unsupported_availability)
        toolchain_path = unsupported_availability / "toolchain.json"
        toolchain = json.loads(toolchain_path.read_text(encoding="utf-8"))
        toolchain["backupAvailabilityPolicy"] = "live-hosts-optional"
        toolchain_data = (json.dumps(toolchain, indent=2, sort_keys=True) + "\n").encode()
        toolchain_path.write_bytes(toolchain_data)
        record_path = unsupported_availability / "ceremony.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["toolImageSHA256"] = hashlib.sha256(toolchain_data).hexdigest()
        record_path.write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        rejected = run(unsupported_availability)
        assert rejected.returncode == 2
        assert "backupAvailabilityPolicy" in rejected.stderr

        unsupported_addresses = temporary / "unsupported-addresses"
        shutil.copytree(prepared, unsupported_addresses)
        toolchain_path = unsupported_addresses / "toolchain.json"
        toolchain = json.loads(toolchain_path.read_text(encoding="utf-8"))
        toolchain["targetAddressPolicy"] = "persistent-config-addresses"
        toolchain_data = (json.dumps(toolchain, indent=2, sort_keys=True) + "\n").encode()
        toolchain_path.write_bytes(toolchain_data)
        record_path = unsupported_addresses / "ceremony.json"
        record = json.loads(record_path.read_text(encoding="utf-8"))
        record["toolImageSHA256"] = hashlib.sha256(toolchain_data).hexdigest()
        record_path.write_text(
            json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        rejected = run(unsupported_addresses)
        assert rejected.returncode == 2
        assert "targetAddressPolicy" in rejected.stderr

    print("Public-only six-role production-key ceremony evidence tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
