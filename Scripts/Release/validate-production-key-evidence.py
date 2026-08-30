#!/usr/bin/env python3
"""Validate public-only Battman production-key ceremony and recovery evidence.

The evidence tree contains no private keys or passwords. It proves that each
required role has a distinct P-256 public identity and that a restored backup
signed a role-bound disposable challenge. Independent review remains a separate
recorded assertion and may be required after code freeze.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (
    decode_dss_signature,
    encode_dss_signature,
)

from release_common import ReleaseError, iter_tree, require_git_commit


EXPECTED_ROLES = {
    "root-r1": "official-trust-root",
    "root-r2": "official-trust-root",
    "root-r3": "official-trust-root",
    "official-plugin-publisher": "official-plugin-publisher",
    "release-checksum": "release-checksum",
    "sdk-example-publisher": "sdk-example-publisher",
}
PRIVATE_KEY_FORMAT = "PKCS8-PBES2-scrypt-AES-256-CBC"
HEX_64 = re.compile(r"^[0-9a-f]{64}$")
CEREMONY_ID = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,126}[a-z0-9])?$")
SSH_FINGERPRINT = re.compile(r"^SHA256:[A-Za-z0-9+/]{43}$")
MAX_JSON_INTEGER = 9_007_199_254_740_991


def _exact(value: object, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ReleaseError(f"{label} has missing or unknown fields")
    return value


def _integer(value: object, minimum: int, maximum: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ReleaseError(f"{label} is outside the supported integer range")
    return value


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ReleaseError(f"JSON contains a duplicate key: {key}")
        value[key] = item
    return value


def _canonical_json(
    path: Path, label: str, maximum_size: int = 256 * 1024
) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_size:
        raise ReleaseError(f"{label} must be one bounded regular file")
    data = path.read_bytes()
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{label} is not strict UTF-8 JSON") from error
    if data != (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"):
        raise ReleaseError(f"{label} is not canonical sorted JSON")
    return value


def _bounded_line(value: object, label: str) -> str:
    if (
        not isinstance(value, str)
        or not 1 <= len(value) <= 256
        or "\n" in value
        or "\r" in value
    ):
        raise ReleaseError(f"{label} must be one bounded line")
    return value


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _public_identity(path: Path) -> tuple[ec.EllipticCurvePublicKey, str]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 16 * 1024:
        raise ReleaseError(f"public key is not one bounded regular file: {path.name}")
    key = serialization.load_pem_public_key(path.read_bytes())
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise ReleaseError(f"public key is not ECDSA P-256: {path.name}")
    raw = key.public_bytes(
        serialization.Encoding.X962,
        serialization.PublicFormat.UncompressedPoint,
    )
    return key, hashlib.sha256(raw).hexdigest()


def _challenge(
    ceremony_id: str,
    role: str,
    key_identifier: str,
    artifact_digest: str,
    artifact_size: int,
) -> bytes:
    return (
        "Battman production-key recovery challenge\n"
        f"ceremony={ceremony_id}\n"
        f"role={role}\n"
        f"keyIdentifier={key_identifier}\n"
        f"privateKeyArtifactSHA256={artifact_digest}\n"
        f"privateKeyArtifactSize={artifact_size}\n"
    ).encode("ascii")


def validate(root: Path, require_reviewed: bool) -> dict[str, object]:
    root = root.expanduser().absolute()
    if not root.is_dir() or root.is_symlink():
        raise ReleaseError("production-key evidence must be one real directory")
    root = root.resolve()
    value = _exact(
        _canonical_json(root / "ceremony.json", "ceremony.json"),
        {
            "backupHosts",
            "ceremonyIdentifier",
            "codeFreezeCommit",
            "generatedAtUnixSeconds",
            "operatorIdentifier",
            "reviewer",
            "roles",
            "schemaVersion",
            "toolImageSHA256",
            "toolVersion",
        },
        "ceremony record",
    )
    if value["schemaVersion"] != 3:
        raise ReleaseError("ceremony record has an unsupported schemaVersion")
    ceremony_id = value["ceremonyIdentifier"]
    if not isinstance(ceremony_id, str) or not CEREMONY_ID.fullmatch(ceremony_id):
        raise ReleaseError("ceremonyIdentifier is malformed")
    generated_at = _integer(
        value["generatedAtUnixSeconds"], 0, MAX_JSON_INTEGER, "generatedAtUnixSeconds"
    )
    tool_digest = value["toolImageSHA256"]
    if not isinstance(tool_digest, str) or not HEX_64.fullmatch(tool_digest):
        raise ReleaseError("toolImageSHA256 must be lowercase SHA-256")
    tool_version = _bounded_line(value["toolVersion"], "toolVersion")
    _bounded_line(value["operatorIdentifier"], "operatorIdentifier")
    toolchain_path = root / "toolchain.json"
    toolchain = _exact(
        _canonical_json(toolchain_path, "toolchain.json", 64 * 1024),
        {
            "backupAvailabilityPolicy",
            "backupHostFingerprints",
            "ceremonyScriptSHA256",
            "cryptographyVersion",
            "hostBuildVersion",
            "hostProductVersion",
            "networkPolicy",
            "opensslExecutableSHA256",
            "opensslVersion",
            "pythonExecutableSHA256",
            "pythonVersion",
            "schemaVersion",
            "targetAddressPolicy",
        },
        "toolchain record",
    )
    if toolchain["schemaVersion"] != 3 or _sha256(toolchain_path) != tool_digest:
        raise ReleaseError("toolchain.json does not match toolImageSHA256")
    if toolchain["networkPolicy"] != "trusted-private-lan-permitted":
        raise ReleaseError("toolchain networkPolicy is unsupported")
    if (
        toolchain["backupAvailabilityPolicy"]
        != "live-pinned-hosts-required-for-backup-only"
    ):
        raise ReleaseError("toolchain backupAvailabilityPolicy is unsupported")
    if toolchain["targetAddressPolicy"] != "manual-private-ipv4-per-live-run":
        raise ReleaseError("toolchain targetAddressPolicy is unsupported")
    for field in (
        "ceremonyScriptSHA256",
        "opensslExecutableSHA256",
        "pythonExecutableSHA256",
    ):
        digest = toolchain[field]
        if not isinstance(digest, str) or not HEX_64.fullmatch(digest):
            raise ReleaseError(f"toolchain {field} must be lowercase SHA-256")
    for field in (
        "hostBuildVersion",
        "hostProductVersion",
        "cryptographyVersion",
        "opensslVersion",
        "pythonVersion",
    ):
        _bounded_line(toolchain[field], f"toolchain {field}")

    backup_records = value["backupHosts"]
    if not isinstance(backup_records, list) or len(backup_records) != 2:
        raise ReleaseError("ceremony record must contain exactly two backup hosts")
    backup_hosts: dict[str, dict[str, Any]] = {}
    for item in backup_records:
        backup = _exact(
            item,
            {
                "hostKeyFingerprint",
                "identifier",
                "offlineStorageConfirmed",
            },
            "backup-host record",
        )
        identifier = backup["identifier"]
        if (
            not isinstance(identifier, str)
            or not CEREMONY_ID.fullmatch(identifier)
            or identifier in backup_hosts
        ):
            raise ReleaseError("backup host has a malformed or duplicate identifier")
        fingerprint = backup["hostKeyFingerprint"]
        if (
            not isinstance(fingerprint, str)
            or not SSH_FINGERPRINT.fullmatch(fingerprint)
            or fingerprint in {
                record["hostKeyFingerprint"] for record in backup_hosts.values()
            }
        ):
            raise ReleaseError("backup host has a malformed or reused host identity")
        if not isinstance(backup["offlineStorageConfirmed"], bool):
            raise ReleaseError("backup host offlineStorageConfirmed is malformed")
        backup_hosts[identifier] = backup
    toolchain_hosts = toolchain["backupHostFingerprints"]
    if not isinstance(toolchain_hosts, list) or toolchain_hosts != sorted(
        record["hostKeyFingerprint"] for record in backup_hosts.values()
    ):
        raise ReleaseError("toolchain backup host fingerprints do not match ceremony backups")

    roles = value["roles"]
    if not isinstance(roles, list) or len(roles) != len(EXPECTED_ROLES):
        raise ReleaseError("ceremony record must contain exactly the six required roles")
    expected_files = {"ceremony.json", "toolchain.json", "keys", "challenges"}
    identifiers: set[str] = set()
    seen_roles: set[str] = set()
    latest_ceremony_verification = generated_at
    for item in roles:
        record = _exact(
            item,
            {
                "backupCopies",
                "backupFiles",
                "challengeFile",
                "challengeSignatureFile",
                "keyIdentifier",
                "privateKeyArtifactFormat",
                "privateKeyArtifactSHA256",
                "privateKeyArtifactSize",
                "publicKeyFile",
                "recoveryVerifiedAtUnixSeconds",
                "role",
                "rotationReviewDueUnixSeconds",
                "scope",
            },
            "key-role record",
        )
        role = record["role"]
        if not isinstance(role, str) or role not in EXPECTED_ROLES or role in seen_roles:
            raise ReleaseError("ceremony record has an unknown or duplicate key role")
        seen_roles.add(role)
        if record["scope"] != EXPECTED_ROLES[role]:
            raise ReleaseError(f"ceremony role has the wrong scope: {role}")
        artifact_digest = record["privateKeyArtifactSHA256"]
        if not isinstance(artifact_digest, str) or not HEX_64.fullmatch(artifact_digest):
            raise ReleaseError(f"ceremony role has a malformed private artifact digest: {role}")
        artifact_size = _integer(
            record["privateKeyArtifactSize"],
            256,
            64 * 1024,
            f"{role} privateKeyArtifactSize",
        )
        if record["privateKeyArtifactFormat"] != PRIVATE_KEY_FORMAT:
            raise ReleaseError(f"ceremony role has the wrong private artifact format: {role}")
        backup_files = record["backupFiles"]
        if not isinstance(backup_files, list) or len(backup_files) != len(backup_hosts):
            raise ReleaseError(f"ceremony role does not bind both backup files: {role}")
        seen_backup_hosts: set[str] = set()
        restore_count = 0
        latest_backup_verification = generated_at
        for backup_item in backup_files:
            backup = _exact(
                backup_item,
                {
                    "artifactSHA256",
                    "artifactSize",
                    "hostIdentifier",
                    "remoteFile",
                    "restoreTested",
                    "storedAtUnixSeconds",
                    "verifiedAtUnixSeconds",
                },
                "role backup-file record",
            )
            host_identifier = backup["hostIdentifier"]
            if host_identifier not in backup_hosts or host_identifier in seen_backup_hosts:
                raise ReleaseError(f"ceremony role has an unknown or reused backup host: {role}")
            seen_backup_hosts.add(host_identifier)
            if (
                backup["artifactSHA256"] != artifact_digest
                or backup["artifactSize"] != artifact_size
                or backup["remoteFile"] != f"{role}.private.pem"
            ):
                raise ReleaseError(f"ceremony role backup does not match its private artifact: {role}")
            stored_at = _integer(
                backup["storedAtUnixSeconds"],
                generated_at,
                MAX_JSON_INTEGER,
                f"{role} {host_identifier} storedAtUnixSeconds",
            )
            verified_at = _integer(
                backup["verifiedAtUnixSeconds"],
                stored_at,
                MAX_JSON_INTEGER,
                f"{role} {host_identifier} verifiedAtUnixSeconds",
            )
            latest_backup_verification = max(latest_backup_verification, verified_at)
            if not isinstance(backup["restoreTested"], bool):
                raise ReleaseError(f"ceremony role backup restoreTested is malformed: {role}")
            restore_count += int(backup["restoreTested"])
        if seen_backup_hosts != set(backup_hosts) or restore_count != 1:
            raise ReleaseError(f"ceremony role must bind two hosts and one tested restore: {role}")
        latest_ceremony_verification = max(
            latest_ceremony_verification, latest_backup_verification
        )
        expected_public = f"keys/{role}.public.pem"
        expected_challenge = f"challenges/{role}.challenge"
        expected_signature = f"challenges/{role}.challenge.p256.sig"
        if (
            record["publicKeyFile"] != expected_public
            or record["challengeFile"] != expected_challenge
            or record["challengeSignatureFile"] != expected_signature
        ):
            raise ReleaseError(f"ceremony role uses noncanonical evidence paths: {role}")
        public_key, identifier = _public_identity(root / expected_public)
        if record["keyIdentifier"] != identifier or identifier in identifiers:
            raise ReleaseError(f"ceremony role has a mismatched or reused key: {role}")
        identifiers.add(identifier)
        if record["backupCopies"] != len(backup_hosts):
            raise ReleaseError(f"{role} backupCopies does not match the evidence")
        recovery_at = _integer(
            record["recoveryVerifiedAtUnixSeconds"],
            latest_backup_verification,
            MAX_JSON_INTEGER,
            f"{role} recoveryVerifiedAtUnixSeconds",
        )
        latest_ceremony_verification = max(latest_ceremony_verification, recovery_at)
        _integer(
            record["rotationReviewDueUnixSeconds"],
            recovery_at + 1,
            MAX_JSON_INTEGER,
            f"{role} rotationReviewDueUnixSeconds",
        )
        challenge_path = root / expected_challenge
        signature_path = root / expected_signature
        if (
            not challenge_path.is_file()
            or challenge_path.is_symlink()
            or challenge_path.stat().st_size > 4096
            or challenge_path.read_bytes() != _challenge(
                ceremony_id,
                role,
                identifier,
                artifact_digest,
                artifact_size,
            )
        ):
            raise ReleaseError(f"ceremony role has a malformed recovery challenge: {role}")
        if (
            not signature_path.is_file()
            or signature_path.is_symlink()
            or not 1 <= signature_path.stat().st_size <= 256
        ):
            raise ReleaseError(f"ceremony role has a malformed recovery signature: {role}")
        signature = signature_path.read_bytes()
        try:
            first, second = decode_dss_signature(signature)
            if encode_dss_signature(first, second) != signature:
                raise ValueError("noncanonical DER")
            public_key.verify(signature, challenge_path.read_bytes(), ec.ECDSA(hashes.SHA256()))
        except (InvalidSignature, ValueError) as error:
            raise ReleaseError(f"ceremony recovery signature failed: {role}") from error
        expected_files.update({expected_public, expected_challenge, expected_signature})

    if seen_roles != set(EXPECTED_ROLES):
        raise ReleaseError("ceremony record omits a required key role")
    actual_files = {relative for relative, _, _ in iter_tree(root)}
    if actual_files != expected_files:
        raise ReleaseError("production-key evidence has missing or unexpected files")

    reviewer = value["reviewer"]
    code_freeze = value["codeFreezeCommit"]
    reviewed = reviewer is not None
    if reviewed:
        reviewer_record = _exact(
            reviewer,
            {
                "backupDigestsCompared",
                "challengesVerified",
                "fingerprintsCompared",
                "identifier",
                "physicalSeparationConfirmed",
                "reviewedAtUnixSeconds",
            },
            "reviewer record",
        )
        _bounded_line(reviewer_record["identifier"], "reviewer identifier")
        if any(
            reviewer_record[field] is not True
            for field in (
                "backupDigestsCompared",
                "challengesVerified",
                "fingerprintsCompared",
                "physicalSeparationConfirmed",
            )
        ):
            raise ReleaseError("reviewer did not attest all production-key checks")
        if any(
            backup["offlineStorageConfirmed"] is not True
            for backup in backup_hosts.values()
        ):
            raise ReleaseError("reviewed backups must be offline and physically separated")
        _integer(
            reviewer_record["reviewedAtUnixSeconds"],
            latest_ceremony_verification,
            MAX_JSON_INTEGER,
            "reviewedAtUnixSeconds",
        )
        if not isinstance(code_freeze, str):
            raise ReleaseError("a reviewed ceremony requires codeFreezeCommit")
        require_git_commit(code_freeze)
    elif code_freeze is not None:
        raise ReleaseError("codeFreezeCommit must remain null until independent review")
    if require_reviewed and not reviewed:
        raise ReleaseError("production-key evidence has not received post-freeze review")

    return {
        "ceremonyIdentifier": ceremony_id,
        "codeFreezeCommit": code_freeze,
        "backupHostCount": len(backup_hosts),
        "backupAvailabilityPolicy": toolchain["backupAvailabilityPolicy"],
        "keyIdentifiers": sorted(identifiers),
        "networkPolicy": toolchain["networkPolicy"],
        "reviewed": reviewed,
        "roleCount": len(roles),
        "schemaVersion": 3,
        "toolImageSHA256": tool_digest,
        "toolVersion": tool_version,
        "targetAddressPolicy": toolchain["targetAddressPolicy"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--require-reviewed", action="store_true")
    arguments = parser.parse_args()
    print(json.dumps(validate(arguments.evidence, arguments.require_reviewed), sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
