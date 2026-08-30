#!/usr/bin/env python3
"""Offline, disposable tests for the owner-only production ceremony tool."""

from __future__ import annotations

import copy
import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/Ceremony/run-production-key-ceremony.py"
SPEC = importlib.util.spec_from_file_location("battman_production_ceremony", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
CEREMONY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CEREMONY)


def expect_failure(callback, message: str) -> None:
    try:
        callback()
    except CEREMONY.CeremonyError:
        return
    raise AssertionError(message)


def pending_fixture() -> dict[str, object]:
    roles = []
    for role, scope in CEREMONY.ROLE_SCOPES.items():
        roles.append({
            "backupCopies": 2,
            "backupFiles": [],
            "challengeFile": f"challenges/{role}.challenge",
            "challengeSignatureFile": f"challenges/{role}.challenge.p256.sig",
            "keyIdentifier": "1" * 64,
            "privateKeyArtifactFormat": CEREMONY.PRIVATE_KEY_FORMAT,
            "privateKeyArtifactSHA256": "2" * 64,
            "privateKeyArtifactSize": 399,
            "publicKeyFile": f"keys/{role}.public.pem",
            "recoveryVerifiedAtUnixSeconds": 0,
            "role": role,
            "rotationReviewDueUnixSeconds": 0,
            "scope": scope,
        })
    return {
        "ceremonyIdentifier": CEREMONY.CEREMONY_IDENTIFIER,
        "generatedAtUnixSeconds": 1,
        "operatorIdentifier": "test-operator",
        "roles": roles,
        "schemaVersion": 1,
        "toolImageSHA256": "3" * 64,
        "toolVersion": "OpenSSL 3 disposable test",
    }


def main() -> None:
    openssl_raw = subprocess.run(
        ["/usr/bin/which", "openssl"], check=True, capture_output=True, text=True
    ).stdout.strip()
    openssl = Path(openssl_raw).resolve()
    with tempfile.TemporaryDirectory(prefix="battman-ceremony-test-") as name:
        private_path = Path(name) / "disposable.private.pem"
        generated = subprocess.run(
            [
                str(openssl),
                "genpkey",
                "-algorithm",
                "EC",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                str(openssl),
                "pkcs8",
                "-topk8",
                "-scrypt",
                "-passout",
                "pass:disposable-test-only",
                "-out",
                str(private_path),
            ],
            input=generated.stdout,
            check=True,
            capture_output=True,
        )
        os.chmod(private_path, 0o400)
        digest, size = CEREMONY.validate_encrypted_private_key(openssl, private_path)
        assert len(digest) == 64 and 256 <= size <= 64 * 1024

        unencrypted = Path(name) / "unencrypted.pem"
        unencrypted.write_bytes(generated.stdout)
        os.chmod(unencrypted, 0o400)
        expect_failure(
            lambda: CEREMONY.validate_encrypted_private_key(openssl, unencrypted),
            "unencrypted private key was accepted",
        )

    pending = pending_fixture()
    roles = CEREMONY.validate_pending_record(pending, "test-operator", "3" * 64)
    assert len(roles) == 6

    extra = copy.deepcopy(pending)
    extra["unexpected"] = True
    expect_failure(
        lambda: CEREMONY.validate_pending_record(extra, "test-operator", "3" * 64),
        "unknown pending-record field was accepted",
    )

    traversal = copy.deepcopy(pending)
    traversal["roles"][0]["publicKeyFile"] = "../private/root.pem"
    expect_failure(
        lambda: CEREMONY.validate_pending_record(traversal, "test-operator", "3" * 64),
        "noncanonical pending-record path was accepted",
    )

    address_targets = [
        {"identifier": "backup-a"},
        {"identifier": "backup-b"},
    ]
    unaddressed = CEREMONY.assign_target_addresses(
        address_targets, [], required=False
    )
    assert all("address" not in target for target in unaddressed)
    addressed = CEREMONY.assign_target_addresses(
        address_targets,
        ["backup-a=192.168.50.7", "backup-b=10.20.30.40"],
        required=True,
    )
    assert [target["address"] for target in addressed] == [
        "192.168.50.7",
        "10.20.30.40",
    ]
    ssh_target = dict(
        addressed[0],
        hostKeyAlias="backup-a",
        knownHostsFile="/private/tmp/disposable-known-hosts",
    )
    ssh_command = CEREMONY.ssh_command(ssh_target)
    assert ssh_command[-1] == "root@192.168.50.7"
    assert "HostKeyAlias=backup-a" in ssh_command
    expect_failure(
        lambda: CEREMONY.assign_target_addresses(address_targets, [], required=True),
        "live phase accepted missing manual addresses",
    )
    expect_failure(
        lambda: CEREMONY.assign_target_addresses(
            address_targets, ["backup-a=192.168.50.7"], required=True
        ),
        "live phase accepted a partial address map",
    )
    expect_failure(
        lambda: CEREMONY.assign_target_addresses(
            address_targets,
            ["backup-a=192.168.50.7", "backup-b=192.168.50.7"],
            required=True,
        ),
        "live phase accepted one address for two identities",
    )
    expect_failure(
        lambda: CEREMONY.assign_target_addresses(
            address_targets,
            ["backup-a=8.8.8.8", "backup-b=10.20.30.40"],
            required=True,
        ),
        "live phase accepted a public address",
    )
    expect_failure(
        lambda: CEREMONY.assign_target_addresses(
            address_targets,
            ["unknown-backup=192.168.50.7", "backup-b=10.20.30.40"],
            required=True,
        ),
        "live phase accepted an unknown identity",
    )

    source = SCRIPT.read_text(encoding="utf-8")
    for forbidden in (
        "hdiutil",
        "getpass",
        "passphrase =",
        "BACK UP ENCRYPTED VAULT",
        "OFFLINE_CONFIRMATION",
        "default_route_exists",
        "active_non_loopback_network_exists",
        "sshTarget",
        '"/sbin/route"',
        '"/sbin/ifconfig"',
    ):
        assert forbidden not in source
    assert CEREMONY.BACKUP_CONFIRMATION == "BACK UP ENCRYPTED PRODUCTION KEYS"
    assert CEREMONY.NETWORK_POLICY == "trusted-private-lan-permitted"
    assert (
        CEREMONY.BACKUP_AVAILABILITY_POLICY
        == "live-pinned-hosts-required-for-backup-only"
    )
    assert CEREMONY.TARGET_ADDRESS_POLICY == "manual-private-ipv4-per-live-run"
    assert '"--target-address"' in source
    source_generate_gate = "if arguments.preflight or arguments.backup:"
    assert source_generate_gate in source
    print("Owner-only production-key ceremony contract tests passed.")


if __name__ == "__main__":
    main()
