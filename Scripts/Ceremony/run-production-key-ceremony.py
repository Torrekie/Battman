#!/usr/bin/env python3
"""Owner-operated Battman production-key ceremony.

This command is deliberately outside normal build and release automation. It
requires an interactive terminal, creates six encrypted P-256 private keys
as six independently passphrased PKCS#8 files, copies only those ciphertexts
to two pinned SSH backup hosts, restores one copy, and emits public-only
evidence.

Never provide a passphrase through chat, an automation assistant, a command
argument, an environment variable, a file, CI, or shell history. OpenSSL reads
each passphrase directly from the controlling terminal; this command never
receives one.
"""

from __future__ import annotations

import argparse
import cryptography
import hashlib
import ipaddress
import json
import os
import re
import resource
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


CEREMONY_IDENTIFIER = "battman-1.1.0-production-keys-1"
CONFIRMATION = "GENERATE BATTMAN 1.1.0 PRODUCTION KEYS"
BACKUP_CONFIRMATION = "BACK UP ENCRYPTED PRODUCTION KEYS"
NETWORK_POLICY = "trusted-private-lan-permitted"
BACKUP_AVAILABILITY_POLICY = "live-pinned-hosts-required-for-backup-only"
TARGET_ADDRESS_POLICY = "manual-private-ipv4-per-live-run"
ROLE_SCOPES = {
    "root-r1": "official-trust-root",
    "root-r2": "official-trust-root",
    "root-r3": "official-trust-root",
    "official-plugin-publisher": "official-plugin-publisher",
    "release-checksum": "release-checksum",
    "sdk-example-publisher": "sdk-example-publisher",
}
PRIVATE_KEY_FORMAT = "PKCS8-PBES2-scrypt-AES-256-CBC"
IDENTIFIER = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,126}[a-z0-9])?$")
SSH_ALIAS = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,252}[A-Za-z0-9])?$")
SSH_FINGERPRINT = re.compile(r"^SHA256:[A-Za-z0-9+/]{43}$")
OPERATOR = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9 ._@+-]{0,126}[A-Za-z0-9])?$")
REMOTE_ROOT = "/private/var/root/BattmanKeyBackups/"
REMOTE_PATH = (
    "/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:"
    "/usr/bin:/bin:/usr/sbin:/sbin"
)


class CeremonyError(RuntimeError):
    pass


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def write_new(path: Path, data: bytes, mode: int) -> None:
    if path.exists() or path.is_symlink():
        raise CeremonyError(f"refusing to overwrite {path}")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        path.unlink(missing_ok=True)
        raise


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def run(
    command: list[str],
    *,
    input_data: bytes | None = None,
    stdout: int | Any = subprocess.PIPE,
    stderr: int | Any = subprocess.PIPE,
    env_extra: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[bytes]:
    environment = {
        "HOME": str(Path.home()),
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/opt/local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/private/tmp",
    }
    if env_extra:
        environment.update(env_extra)
    result = subprocess.run(
        command,
        input=input_data,
        stdout=stdout,
        stderr=stderr,
        check=False,
        env=environment,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip() if result.stderr else ""
        raise CeremonyError(f"command failed ({result.returncode}): {command[0]}: {detail}")
    return result


def output(command: list[str]) -> str:
    return run(command).stdout.decode("utf-8", "strict").strip()


def require_regular(path: Path, label: str, maximum_size: int) -> Path:
    lexical = path.expanduser().absolute()
    entry = lexical.lstat()
    if (
        not stat.S_ISREG(entry.st_mode)
        or entry.st_nlink != 1
        or entry.st_size > maximum_size
    ):
        raise CeremonyError(f"{label} must be one bounded single-link regular file")
    return lexical


def strict_json(path: Path, label: str) -> dict[str, Any]:
    path = require_regular(path, label, 64 * 1024)
    if path.stat().st_mode & 0o077:
        raise CeremonyError(f"{label} permissions must not grant group/other access")
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise CeremonyError(f"{label} contains a duplicate key: {key}")
            value[key] = item
        return value
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=unique_object
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CeremonyError(f"{label} is not strict UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise CeremonyError(f"{label} must contain one JSON object")
    return value


def validate_pending_record(
    pending: dict[str, Any], operator: str, tool_digest: str
) -> list[dict[str, object]]:
    expected_top = {
        "ceremonyIdentifier",
        "generatedAtUnixSeconds",
        "operatorIdentifier",
        "roles",
        "schemaVersion",
        "toolImageSHA256",
        "toolVersion",
    }
    if set(pending) != expected_top:
        raise CeremonyError("pending backup record has missing or unknown fields")
    if (
        pending["schemaVersion"] != 1
        or pending["ceremonyIdentifier"] != CEREMONY_IDENTIFIER
        or pending["operatorIdentifier"] != operator
        or pending["toolImageSHA256"] != tool_digest
        or isinstance(pending["generatedAtUnixSeconds"], bool)
        or not isinstance(pending["generatedAtUnixSeconds"], int)
        or pending["generatedAtUnixSeconds"] < 0
        or not isinstance(pending["toolVersion"], str)
        or not 1 <= len(pending["toolVersion"]) <= 256
        or "\n" in pending["toolVersion"]
        or "\r" in pending["toolVersion"]
    ):
        raise CeremonyError("pending backup record does not match this ceremony/toolchain")
    raw_roles = pending["roles"]
    if not isinstance(raw_roles, list) or len(raw_roles) != len(ROLE_SCOPES):
        raise CeremonyError("pending backup record has the wrong production roles")
    role_fields = {
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
    }
    seen: set[str] = set()
    roles: list[dict[str, object]] = []
    for raw in raw_roles:
        if not isinstance(raw, dict) or set(raw) != role_fields:
            raise CeremonyError("pending role has missing or unknown fields")
        role = raw["role"]
        if not isinstance(role, str) or role not in ROLE_SCOPES or role in seen:
            raise CeremonyError("pending role is unknown or duplicated")
        seen.add(role)
        if (
            raw["scope"] != ROLE_SCOPES[role]
            or raw["backupCopies"] != 2
            or raw["backupFiles"] != []
            or raw["challengeFile"] != f"challenges/{role}.challenge"
            or raw["challengeSignatureFile"] != f"challenges/{role}.challenge.p256.sig"
            or raw["publicKeyFile"] != f"keys/{role}.public.pem"
            or raw["privateKeyArtifactFormat"] != PRIVATE_KEY_FORMAT
            or raw["recoveryVerifiedAtUnixSeconds"] != 0
            or raw["rotationReviewDueUnixSeconds"] != 0
            or not isinstance(raw["keyIdentifier"], str)
            or not re.fullmatch(r"[0-9a-f]{64}", raw["keyIdentifier"])
            or not isinstance(raw["privateKeyArtifactSHA256"], str)
            or not re.fullmatch(r"[0-9a-f]{64}", raw["privateKeyArtifactSHA256"])
            or isinstance(raw["privateKeyArtifactSize"], bool)
            or not isinstance(raw["privateKeyArtifactSize"], int)
            or not 256 <= raw["privateKeyArtifactSize"] <= 64 * 1024
        ):
            raise CeremonyError(f"pending role is malformed: {role}")
        roles.append(dict(raw))
    if seen != set(ROLE_SCOPES):
        raise CeremonyError("pending backup record omits a production role")
    return roles


def load_targets(path: Path) -> list[dict[str, str]]:
    value = strict_json(path, "target configuration")
    if set(value) != {"backupTargets", "ceremonyIdentifier", "schemaVersion"}:
        raise CeremonyError("target configuration has missing or unknown fields")
    if value["schemaVersion"] != 2 or value["ceremonyIdentifier"] != CEREMONY_IDENTIFIER:
        raise CeremonyError("target configuration has the wrong schema or ceremony")
    raw_targets = value["backupTargets"]
    if not isinstance(raw_targets, list) or len(raw_targets) != 2:
        raise CeremonyError("target configuration must contain exactly two backup hosts")
    targets: list[dict[str, str]] = []
    identifiers: set[str] = set()
    fingerprints: set[str] = set()
    required = {
        "hostKeyAlias",
        "hostKeyFingerprint",
        "identifier",
        "knownHostsFile",
        "remoteDirectory",
    }
    for item in raw_targets:
        if not isinstance(item, dict) or set(item) != required:
            raise CeremonyError("backup target has missing or unknown fields")
        if not all(isinstance(item[field], str) for field in required):
            raise CeremonyError("backup target fields must be strings")
        identifier = item["identifier"]
        if not IDENTIFIER.fullmatch(identifier) or identifier in identifiers:
            raise CeremonyError("backup target identifier is malformed or reused")
        identifiers.add(identifier)
        fingerprint = item["hostKeyFingerprint"]
        if not SSH_FINGERPRINT.fullmatch(fingerprint) or fingerprint in fingerprints:
            raise CeremonyError("backup host fingerprint is malformed or reused")
        fingerprints.add(fingerprint)
        alias = item["hostKeyAlias"]
        if not SSH_ALIAS.fullmatch(alias):
            raise CeremonyError("backup host-key alias is malformed")
        known_hosts = require_regular(
            Path(item["knownHostsFile"]), "dedicated known-hosts file", 64 * 1024
        )
        if known_hosts.stat().st_mode & 0o077:
            raise CeremonyError("dedicated known-hosts file permissions must be 0600")
        item["knownHostsFile"] = str(known_hosts)
        expected_directory = REMOTE_ROOT + CEREMONY_IDENTIFIER
        if item["remoteDirectory"] != expected_directory:
            raise CeremonyError("backup target uses an unapproved remote directory")
        targets.append(dict(item))
    return targets


def assign_target_addresses(
    targets: list[dict[str, str]],
    assignments: list[str],
    *,
    required: bool,
) -> list[dict[str, str]]:
    if not assignments:
        if required:
            identifiers = ", ".join(target["identifier"] for target in targets)
            raise CeremonyError(
                "this phase requires one --target-address IDENTIFIER=PRIVATE_IPV4 "
                f"for each of: {identifiers}"
            )
        return [dict(target) for target in targets]
    if len(assignments) != len(targets):
        raise CeremonyError("target-address overrides must cover every backup target exactly once")
    expected = {target["identifier"] for target in targets}
    resolved: dict[str, str] = {}
    addresses: set[str] = set()
    for assignment in assignments:
        identifier, separator, address = assignment.partition("=")
        if not separator or not identifier or not address or "=" in address:
            raise CeremonyError("target-address must use IDENTIFIER=PRIVATE_IPV4")
        if identifier not in expected:
            raise CeremonyError(f"target-address names an unknown backup target: {identifier}")
        if identifier in resolved:
            raise CeremonyError(f"target-address repeats a backup target: {identifier}")
        try:
            parsed = ipaddress.ip_address(address)
        except ValueError as error:
            raise CeremonyError("target-address must contain a private IPv4 literal") from error
        if not isinstance(parsed, ipaddress.IPv4Address) or not parsed.is_private:
            raise CeremonyError("target-address must contain a private IPv4 literal")
        canonical = str(parsed)
        if canonical in addresses:
            raise CeremonyError("backup targets must use distinct current addresses")
        addresses.add(canonical)
        resolved[identifier] = canonical
    if set(resolved) != expected:
        raise CeremonyError("target-address overrides must cover every backup target exactly once")
    return [dict(target, address=resolved[target["identifier"]]) for target in targets]


def ssh_command(target: dict[str, str]) -> list[str]:
    address = target.get("address")
    if not isinstance(address, str):
        raise CeremonyError(f"no current address supplied for {target['identifier']}")
    command = [
        "/usr/bin/ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f'UserKnownHostsFile="{target["knownHostsFile"]}"',
        "-o",
        "GlobalKnownHostsFile=/dev/null",
        "-o",
        "HostKeyAlgorithms=ssh-ed25519",
    ]
    command.extend(["-o", f"HostKeyAlias={target['hostKeyAlias']}"])
    command.append(f"root@{address}")
    return command


def verify_known_host(target: dict[str, str]) -> None:
    known = run([
        "/usr/bin/ssh-keygen",
        "-F",
        target["hostKeyAlias"],
        "-f",
        target["knownHostsFile"],
    ]).stdout
    if not known:
        raise CeremonyError(f"no pinned SSH key for {target['hostKeyAlias']}")
    key_lines = b"".join(
        line for line in known.splitlines(keepends=True) if not line.startswith(b"#")
    )
    if not key_lines:
        raise CeremonyError(f"no usable pinned SSH key for {target['hostKeyAlias']}")
    fingerprints = run(
        ["/usr/bin/ssh-keygen", "-lf", "-"], input_data=key_lines
    ).stdout.decode()
    if target["hostKeyFingerprint"] not in fingerprints:
        raise CeremonyError(f"pinned SSH fingerprint mismatch for {target['identifier']}")


def remote_preflight(target: dict[str, str], *, require_empty: bool) -> None:
    remote_directory = shlex.quote(target["remoteDirectory"])
    partial_checks = " ".join(
        f"test ! -e {shlex.quote(target['remoteDirectory'] + '/.' + role + '.private.pem.partial')}; "
        f"test ! -L {shlex.quote(target['remoteDirectory'] + '/.' + role + '.private.pem.partial')};"
        for role in ROLE_SCOPES
    )
    final_checks = " ".join(
        f"test ! -e {shlex.quote(target['remoteDirectory'] + '/' + role + '.private.pem')}; "
        f"test ! -L {shlex.quote(target['remoteDirectory'] + '/' + role + '.private.pem')};"
        for role in ROLE_SCOPES
    ) if require_empty else ""
    script = (
        f"PATH={REMOTE_PATH}; export PATH; set -eu; "
        f"test -d {remote_directory}; test ! -L {remote_directory}; "
        f"{partial_checks} {final_checks} "
        f"test \"$(stat -f %Lp {remote_directory})\" = 700; "
        f"test \"$(stat -f %Su:%Sg {remote_directory})\" = root:wheel; "
        f"df -k {remote_directory} >/dev/null; "
        "command -v cat >/dev/null; command -v chmod >/dev/null; "
        "command -v sha256sum >/dev/null; command -v stat >/dev/null; "
        "printf ready"
    )
    result = run(
        [*ssh_command(target), script],
        env_extra={"BATTMAN_CEREMONY_KNOWN_HOSTS": target["knownHostsFile"]},
    ).stdout.decode("ascii", "strict")
    if result != "ready":
        raise CeremonyError(f"unexpected preflight response from {target['identifier']}")


def key_identifier(public_path: Path) -> str:
    key = serialization.load_pem_public_key(public_path.read_bytes())
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise CeremonyError("generated public key is not ECDSA P-256")
    raw = key.public_bytes(
        serialization.Encoding.X962,
        serialization.PublicFormat.UncompressedPoint,
    )
    return hashlib.sha256(raw).hexdigest()


def interactive_environment() -> dict[str, str]:
    return {
        "HOME": str(Path.home()),
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/opt/local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/private/tmp",
    }


def run_interactive(command: list[str]) -> None:
    result = subprocess.run(command, check=False, env=interactive_environment())
    if result.returncode:
        raise CeremonyError(f"interactive command failed ({result.returncode}): {command[0]}")


def validate_encrypted_private_key(openssl: Path, private_path: Path) -> tuple[str, int]:
    private_path = require_regular(private_path, "encrypted private key", 64 * 1024)
    if private_path.stat().st_mode & 0o177:
        raise CeremonyError("encrypted private key permissions must be 0400 or 0600")
    if not private_path.read_bytes().startswith(b"-----BEGIN ENCRYPTED PRIVATE KEY-----\n"):
        raise CeremonyError("private key is not encrypted PKCS#8 PEM")
    structure = output([str(openssl), "asn1parse", "-in", str(private_path), "-inform", "PEM", "-i"])
    if ":scrypt" not in structure or ":aes-256-cbc" not in structure:
        raise CeremonyError("private key does not use scrypt plus AES-256-CBC")
    return sha256_file(private_path), private_path.stat().st_size


def generate_keys(
    openssl: Path,
    private_directory: Path,
    evidence: Path,
) -> list[dict[str, object]]:
    public_directory = evidence / "keys"
    private_directory.mkdir(mode=0o700)
    public_directory.mkdir(mode=0o755)
    roles: list[dict[str, object]] = []
    for role, scope in ROLE_SCOPES.items():
        print(f"\nGenerating {role}. Use a unique high-entropy passphrase for this role.")
        private_path = private_directory / f"{role}.private.pem"
        evidence_public = public_directory / f"{role}.public.pem"
        generator = subprocess.Popen(
            [
                str(openssl),
                "genpkey",
                "-algorithm",
                "EC",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
            ],
            stdout=subprocess.PIPE,
            env=interactive_environment(),
        )
        assert generator.stdout is not None
        encryptor = subprocess.run(
            [
                str(openssl),
                "pkcs8",
                "-topk8",
                "-scrypt",
                "-out",
                str(private_path),
            ],
            stdin=generator.stdout,
            check=False,
            env=interactive_environment(),
        )
        generator.stdout.close()
        generator_status = generator.wait()
        if generator_status or encryptor.returncode:
            private_path.unlink(missing_ok=True)
            raise CeremonyError(f"encrypted key generation failed for {role}")
        os.chmod(private_path, 0o400)
        artifact_digest, artifact_size = validate_encrypted_private_key(openssl, private_path)
        print(f"Validate and export the public key for {role}; enter the same role passphrase.")
        temporary_descriptor, temporary_name = tempfile.mkstemp(
            prefix=f"battman-{role}-public-", suffix=".pem", dir="/private/tmp"
        )
        os.close(temporary_descriptor)
        temporary_public = Path(temporary_name)
        try:
            run_interactive(
                [
                    str(openssl),
                    "pkey",
                    "-in",
                    str(private_path),
                    "-check",
                    "-pubout",
                    "-out",
                    str(temporary_public),
                ],
            )
            identifier = key_identifier(temporary_public)
            write_new(evidence_public, temporary_public.read_bytes(), 0o644)
        finally:
            temporary_public.unlink(missing_ok=True)
        roles.append({
            "backupCopies": 2,
            "backupFiles": [],
            "challengeFile": f"challenges/{role}.challenge",
            "challengeSignatureFile": f"challenges/{role}.challenge.p256.sig",
            "keyIdentifier": identifier,
            "privateKeyArtifactFormat": PRIVATE_KEY_FORMAT,
            "privateKeyArtifactSHA256": artifact_digest,
            "privateKeyArtifactSize": artifact_size,
            "publicKeyFile": f"keys/{role}.public.pem",
            "recoveryVerifiedAtUnixSeconds": 0,
            "role": role,
            "rotationReviewDueUnixSeconds": 0,
            "scope": scope,
        })
    if len({record["keyIdentifier"] for record in roles}) != len(ROLE_SCOPES):
        raise CeremonyError("generated production roles do not have distinct public keys")
    return roles


def upload_private_key(
    target: dict[str, str], role: str, private_path: Path
) -> tuple[str, int, int]:
    expected_digest = sha256_file(private_path)
    expected_size = private_path.stat().st_size
    remote_key = target["remoteDirectory"] + f"/{role}.private.pem"
    partial = target["remoteDirectory"] + f"/.{role}.private.pem.partial"
    script = (
        f"PATH={REMOTE_PATH}; export PATH; set -eu; umask 077; "
        f"target={shlex.quote(remote_key)}; partial={shlex.quote(partial)}; "
        f"expected_digest={expected_digest}; expected_size={expected_size}; "
        "test ! -L \"$target\"; test ! -e \"$partial\"; test ! -L \"$partial\"; "
        "if test -e \"$target\"; then test -f \"$target\"; "
        "test \"$(stat -f %l \"$target\")\" = 1; "
        "test \"$(stat -f %Su:%Sg \"$target\")\" = root:wheel; "
        "else trap 'if test -e \"$partial\" || test -L \"$partial\"; "
        "then unlink \"$partial\"; fi' EXIT HUP INT TERM; "
        "set -C; cat > \"$partial\"; set +C; chmod 600 \"$partial\"; "
        "test \"$(sha256sum \"$partial\" | awk '{print $1}')\" = \"$expected_digest\"; "
        "test \"$(stat -f %z \"$partial\")\" = \"$expected_size\"; "
        "mv \"$partial\" \"$target\"; trap - EXIT HUP INT TERM; fi; "
        "chmod 400 \"$target\"; "
        "test ! -L \"$target\"; test -f \"$target\"; "
        "test \"$(stat -f %Lp \"$target\")\" = 400; "
        "test \"$(stat -f %Su:%Sg \"$target\")\" = root:wheel; "
        "test \"$(stat -f %l \"$target\")\" = 1; "
        "printf '%s %s\\n' \"$(sha256sum \"$target\" | awk '{print $1}')\" "
        "\"$(stat -f %z \"$target\")\""
    )
    with private_path.open("rb") as stream:
        result = subprocess.run(
            [*ssh_command(target), script],
            stdin=stream,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env={
                "BATTMAN_CEREMONY_KNOWN_HOSTS": target["knownHostsFile"],
                "HOME": str(Path.home()),
                "LANG": "C",
                "LC_ALL": "C",
                "PATH": "/usr/bin:/bin",
            },
        )
    if result.returncode:
        raise CeremonyError(
            f"backup upload failed for {target['identifier']}: "
            + result.stderr.decode("utf-8", "replace").strip()
        )
    fields = result.stdout.decode("ascii", "strict").strip().split()
    if len(fields) != 2 or not re.fullmatch(r"[0-9a-f]{64}", fields[0]):
        raise CeremonyError(f"malformed backup verification from {target['identifier']}")
    return fields[0], int(fields[1]), int(time.time())


def download_private_key(
    target: dict[str, str], role: str, destination: Path
) -> None:
    remote_key = target["remoteDirectory"] + f"/{role}.private.pem"
    quoted_key = shlex.quote(remote_key)
    script = (
        f"PATH={REMOTE_PATH}; export PATH; set -eu; "
        f"test ! -L {quoted_key}; test -f {quoted_key}; "
        f"test \"$(stat -f %Lp {quoted_key})\" = 400; "
        f"test \"$(stat -f %Su:%Sg {quoted_key})\" = root:wheel; "
        f"test \"$(stat -f %l {quoted_key})\" = 1; cat {quoted_key}"
    )
    descriptor = os.open(
        destination,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
        0o600,
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            result = subprocess.run(
                [*ssh_command(target), script],
                stdout=stream,
                stderr=subprocess.PIPE,
                check=False,
                env={
                    "BATTMAN_CEREMONY_KNOWN_HOSTS": target["knownHostsFile"],
                    "HOME": str(Path.home()),
                    "LANG": "C",
                    "LC_ALL": "C",
                    "PATH": "/usr/bin:/bin",
                },
            )
            stream.flush()
            os.fsync(stream.fileno())
        if result.returncode:
            raise CeremonyError(
                f"backup restore download failed for {target['identifier']}: "
                + result.stderr.decode("utf-8", "replace").strip()
            )
    except Exception:
        destination.unlink(missing_ok=True)
        raise


def recovery_challenges(
    openssl: Path,
    restored_directory: Path,
    evidence: Path,
    roles: list[dict[str, object]],
) -> int:
    challenges = evidence / "challenges"
    if challenges.exists() or challenges.is_symlink():
        if not challenges.is_dir() or challenges.is_symlink():
            raise CeremonyError("recovery challenges path is not one real directory")
    else:
        challenges.mkdir(mode=0o755)
    recovery_time = int(time.time())
    for role_record in roles:
        role = str(role_record["role"])
        public_path = evidence / str(role_record["publicKeyFile"])
        restored_private = restored_directory / f"{role}.private.pem"
        artifact_digest, artifact_size = validate_encrypted_private_key(
            openssl, restored_private
        )
        if (
            artifact_digest != role_record["privateKeyArtifactSHA256"]
            or artifact_size != role_record["privateKeyArtifactSize"]
        ):
            raise CeremonyError(f"restored encrypted private key mismatch for {role}")
        challenge = challenges / f"{role}.challenge"
        signature = challenges / f"{role}.challenge.p256.sig"
        challenge_data = (
            "Battman production-key recovery challenge\n"
            f"ceremony={CEREMONY_IDENTIFIER}\n"
            f"role={role}\n"
            f"keyIdentifier={role_record['keyIdentifier']}\n"
            f"privateKeyArtifactSHA256={artifact_digest}\n"
            f"privateKeyArtifactSize={artifact_size}\n"
        ).encode("ascii")
        if challenge.exists() or challenge.is_symlink():
            if (
                not challenge.is_file()
                or challenge.is_symlink()
                or challenge.read_bytes() != challenge_data
            ):
                raise CeremonyError(f"existing recovery challenge is invalid for {role}")
        else:
            write_new(challenge, challenge_data, 0o644)
        if signature.exists() or signature.is_symlink():
            if not signature.is_file() or signature.is_symlink():
                raise CeremonyError(f"existing recovery signature is invalid for {role}")
            run(
                [
                    str(openssl),
                    "dgst",
                    "-sha256",
                    "-verify",
                    str(public_path),
                    "-signature",
                    str(signature),
                    str(challenge),
                ]
            )
            role_record["recoveryVerifiedAtUnixSeconds"] = recovery_time
            role_record["rotationReviewDueUnixSeconds"] = recovery_time + 365 * 24 * 60 * 60
            continue
        print(f"Recovery-test {role}; enter its role passphrase.")
        temporary_descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{role}.", suffix=".sig", dir=challenges
        )
        os.close(temporary_descriptor)
        temporary_signature = Path(temporary_name)
        try:
            run_interactive(
                [
                    str(openssl),
                    "dgst",
                    "-sha256",
                    "-sign",
                    str(restored_private),
                    "-out",
                    str(temporary_signature),
                    str(challenge),
                ],
            )
            run(
                [
                    str(openssl),
                    "dgst",
                    "-sha256",
                    "-verify",
                    str(public_path),
                    "-signature",
                    str(temporary_signature),
                    str(challenge),
                ]
            )
            write_new(signature, temporary_signature.read_bytes(), 0o644)
        finally:
            temporary_signature.unlink(missing_ok=True)
        role_record["recoveryVerifiedAtUnixSeconds"] = recovery_time
        role_record["rotationReviewDueUnixSeconds"] = recovery_time + 365 * 24 * 60 * 60
    return recovery_time


def toolchain_record(script: Path, openssl: Path, targets: list[dict[str, str]]) -> dict[str, object]:
    product = output(["/usr/bin/sw_vers", "-productVersion"])
    build = output(["/usr/bin/sw_vers", "-buildVersion"])
    openssl_version = output([str(openssl), "version"])
    return {
        "backupAvailabilityPolicy": BACKUP_AVAILABILITY_POLICY,
        "backupHostFingerprints": sorted(target["hostKeyFingerprint"] for target in targets),
        "ceremonyScriptSHA256": sha256_file(script),
        "cryptographyVersion": cryptography.__version__,
        "hostBuildVersion": build,
        "hostProductVersion": product,
        "networkPolicy": NETWORK_POLICY,
        "opensslExecutableSHA256": sha256_file(openssl),
        "opensslVersion": openssl_version,
        "pythonExecutableSHA256": sha256_file(Path(sys.executable).resolve()),
        "pythonVersion": sys.version.split()[0],
        "schemaVersion": 3,
        "targetAddressPolicy": TARGET_ADDRESS_POLICY,
    }


def preflight(arguments: argparse.Namespace) -> tuple[list[dict[str, str]], Path, Path]:
    if sys.platform != "darwin":
        raise CeremonyError("production ceremony requires macOS")
    script = Path(__file__).resolve()
    repository = script.parents[2]
    output_parent = arguments.output_directory.expanduser().absolute().parent
    if not output_parent.is_dir() or output_parent.is_symlink():
        raise CeremonyError("output parent must be one existing real directory")
    if output_parent.stat().st_mode & 0o077:
        raise CeremonyError("output parent permissions must be 0700")
    output_directory = arguments.output_directory.expanduser().absolute()
    if arguments.backup:
        if not output_directory.is_dir() or output_directory.is_symlink():
            raise CeremonyError("backup phase requires the generated ceremony directory")
        if output_directory.stat().st_mode & 0o077:
            raise CeremonyError("generated ceremony directory permissions must be 0700")
    elif output_directory.exists() or output_directory.is_symlink():
        raise CeremonyError("ceremony output directory already exists")
    try:
        output_directory.relative_to(repository)
    except ValueError:
        pass
    else:
        raise CeremonyError("private ceremony output must remain outside the repository")
    openssl = arguments.openssl_executable.expanduser().absolute().resolve()
    require_regular(openssl, "OpenSSL executable", 64 * 1024 * 1024)
    if not output([str(openssl), "version"]).startswith("OpenSSL 3."):
        raise CeremonyError("production ceremony requires reviewed OpenSSL 3.x")
    targets = assign_target_addresses(
        load_targets(arguments.target_config),
        arguments.target_address,
        required=arguments.preflight or arguments.backup,
    )
    for target in targets:
        verify_known_host(target)
    if arguments.preflight or arguments.backup:
        for target in targets:
            remote_preflight(target, require_empty=not arguments.backup)
    return targets, openssl, script


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-config", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--operator-identifier", required=True)
    parser.add_argument(
        "--target-address",
        action="append",
        default=[],
        metavar="IDENTIFIER=PRIVATE_IPV4",
        help="current private IPv4 for one pinned backup identity; repeat per target",
    )
    parser.add_argument(
        "--openssl-executable", type=Path, default=Path("/opt/local/bin/openssl")
    )
    phases = parser.add_mutually_exclusive_group(required=True)
    phases.add_argument("--preflight", action="store_true")
    phases.add_argument("--generate", action="store_true")
    phases.add_argument("--backup", action="store_true")
    arguments = parser.parse_args()
    if not OPERATOR.fullmatch(arguments.operator_identifier):
        raise CeremonyError("operator identifier is malformed")
    targets, openssl, script = preflight(arguments)
    toolchain = toolchain_record(script, openssl, targets)
    if arguments.preflight:
        print(json.dumps({
            "backupTargetAddresses": {
                target["identifier"]: target["address"] for target in targets
            },
            "backupTargets": [target["identifier"] for target in targets],
            "ceremonyIdentifier": CEREMONY_IDENTIFIER,
            "fileVaultStatus": output(["/usr/bin/fdesetup", "status"]),
            "opensslVersion": toolchain["opensslVersion"],
            "outputDirectory": str(arguments.output_directory.expanduser().absolute()),
            "status": "prepared-no-key-generated",
        }, indent=2, sort_keys=True))
        return 0

    if not sys.stdin.isatty() or not sys.stderr.isatty() or os.environ.get("CI"):
        raise CeremonyError("production ceremony requires a local interactive TTY outside CI")
    os.umask(0o077)
    output_directory = arguments.output_directory.expanduser().absolute()
    toolchain_data = canonical_json(toolchain)
    if arguments.generate:
        print("\nThis creates SIX long-lived Battman production private keys.")
        print("Each passphrase is read directly by OpenSSL and is not recoverable by this script.")
        if input(f"Type exactly {CONFIRMATION!r}: ") != CONFIRMATION:
            raise CeremonyError("production-key confirmation was not provided")
        print("\nTrusted-LAN mode: network access remains available by owner decision.")
        print("The pinned devices may sleep during generation, but both must be reachable")
        print("for --backup. Avoid unrelated network activity until recovery checks finish.")
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        output_directory.mkdir(mode=0o700)
        evidence = output_directory / "ProductionKeyEvidence"
        evidence.mkdir(mode=0o755)
        write_new(evidence / "toolchain.json", toolchain_data, 0o644)
        roles = generate_keys(openssl, output_directory / "private", evidence)
        pending = {
            "ceremonyIdentifier": CEREMONY_IDENTIFIER,
            "generatedAtUnixSeconds": int(time.time()),
            "operatorIdentifier": arguments.operator_identifier,
            "roles": roles,
            "schemaVersion": 1,
            "toolImageSHA256": hashlib.sha256(toolchain_data).hexdigest(),
            "toolVersion": str(toolchain["opensslVersion"]),
        }
        write_new(output_directory / "pending-backup.json", canonical_json(pending), 0o600)
        print("\nGeneration complete. Keep the trusted backup LAN connected.")
        print("Rerun the same command with --backup; do not regenerate these keys.")
        return 0

    evidence = output_directory / "ProductionKeyEvidence"
    completed_record = evidence / "ceremony.json"
    if completed_record.exists() or completed_record.is_symlink():
        validator = script.parents[1] / "Release" / "validate-production-key-evidence.py"
        report = output([sys.executable, str(validator), str(evidence)])
        print("Ceremony backup and public recovery evidence are already complete:")
        print(report)
        return 0

    if input(f"Type exactly {BACKUP_CONFIRMATION!r}: ") != BACKUP_CONFIRMATION:
        raise CeremonyError("backup confirmation was not provided")
    if not output_directory.is_dir() or output_directory.is_symlink():
        raise CeremonyError("generated ceremony directory is missing")
    pending = strict_json(output_directory / "pending-backup.json", "pending backup record")
    roles = validate_pending_record(
        pending,
        arguments.operator_identifier,
        hashlib.sha256(toolchain_data).hexdigest(),
    )
    private_directory = output_directory / "private"
    for target in targets:
        remote_preflight(target, require_empty=False)
    for role_record in roles:
        role = str(role_record["role"])
        private_path = private_directory / f"{role}.private.pem"
        public_path = evidence / str(role_record["publicKeyFile"])
        digest, size = validate_encrypted_private_key(openssl, private_path)
        if digest != role_record["privateKeyArtifactSHA256"] or size != role_record["privateKeyArtifactSize"]:
            raise CeremonyError(f"local encrypted key changed before backup: {role}")
        if key_identifier(require_regular(public_path, "public key", 16 * 1024)) != role_record["keyIdentifier"]:
            raise CeremonyError(f"local public key changed before backup: {role}")
        for index, target in enumerate(targets):
            stored_at = int(time.time())
            remote_digest, remote_size, verified_at = upload_private_key(target, role, private_path)
            if remote_digest != digest or remote_size != size:
                raise CeremonyError(f"remote backup digest/size mismatch for {role} on {target['identifier']}")
            role_record["backupFiles"].append({
                "artifactSHA256": digest,
                "artifactSize": size,
                "hostIdentifier": target["identifier"],
                "remoteFile": f"{role}.private.pem",
                "restoreTested": index == 0,
                "storedAtUnixSeconds": stored_at,
                "verifiedAtUnixSeconds": verified_at,
            })

    restored_directory = Path(tempfile.mkdtemp(prefix="battman-production-restore-", dir="/private/tmp"))
    try:
        for role_record in roles:
            role = str(role_record["role"])
            download_private_key(targets[0], role, restored_directory / f"{role}.private.pem")
        recovery_challenges(openssl, restored_directory, evidence, roles)
    finally:
        for path in restored_directory.iterdir():
            path.unlink(missing_ok=True)
        restored_directory.rmdir()

    ceremony = {
        "backupHosts": [
            {
                "hostKeyFingerprint": target["hostKeyFingerprint"],
                "identifier": target["identifier"],
                "offlineStorageConfirmed": False,
            }
            for target in targets
        ],
        "ceremonyIdentifier": CEREMONY_IDENTIFIER,
        "codeFreezeCommit": None,
        "generatedAtUnixSeconds": pending["generatedAtUnixSeconds"],
        "operatorIdentifier": arguments.operator_identifier,
        "reviewer": None,
        "roles": roles,
        "schemaVersion": 3,
        "toolImageSHA256": hashlib.sha256(toolchain_data).hexdigest(),
        "toolVersion": str(toolchain["opensslVersion"]),
    }
    write_new(evidence / "ceremony.json", canonical_json(ceremony), 0o644)
    validator = script.parents[1] / "Release" / "validate-production-key-evidence.py"
    report = output([sys.executable, str(validator), str(evidence)])
    print("\nPrepared production-key ceremony completed. Public validator report:")
    print(report)
    print(f"Encrypted local role files: {private_directory}")
    print(f"Public-only evidence: {evidence}")
    print("Both remote copies are verified; exactly one was restored and challenge-tested.")
    print("offlineStorageConfirmed remains false until the devices are powered down and physically separated.")
    print("Post-freeze independent review and production signing remain separate release gates.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CeremonyError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
