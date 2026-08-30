#!/usr/bin/env python3
"""Generate and validate Battman's identity embedded in a host Mach-O.

The identity is deliberately small and canonical.  A clean Release identity
binds the executable to the exact Git commit and tree used by the release
pipeline.  Dirty engineering builds remain identifiable, but cannot satisfy a
strict release check.
"""

from __future__ import annotations

import json
import os
import re
import stat
import struct
import tempfile
from pathlib import Path
from typing import Any

from release_common import ReleaseError, require_git_commit, require_version, run


SCHEMA_VERSION = 1
SEGMENT_NAME = "__TEXT"
SECTION_NAME = "__btidentity"
MAX_IDENTITY_SIZE = 4096
MAX_EXECUTABLE_SIZE = 128 * 1024 * 1024
MAX_LOAD_COMMAND_SIZE = 4 * 1024 * 1024
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 2
LC_SEGMENT_64 = 0x19
GIT_OBJECT_ID = re.compile(r"^[0-9a-f]{40}$")
BUNDLE_IDENTIFIER = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"
)
IDENTITY_FIELDS = {
    "configuration",
    "productIdentifier",
    "schemaVersion",
    "sourceCommit",
    "sourceDirty",
    "sourceTree",
    "version",
}


def require_git_object_id(value: object, label: str) -> str:
    if not isinstance(value, str) or not GIT_OBJECT_ID.fullmatch(value):
        raise ReleaseError(f"{label} must be a full lowercase 40-hex Git object ID")
    return value


def require_configuration(value: object) -> str:
    if value not in ("Debug", "Release"):
        raise ReleaseError("build identity configuration must be Debug or Release")
    return str(value)


def require_product_identifier(value: object) -> str:
    if (
        not isinstance(value, str)
        or len(value) > 255
        or not BUNDLE_IDENTIFIER.fullmatch(value)
    ):
        raise ReleaseError("build identity product identifier is malformed")
    return value


def _git(repo: Path, *arguments: str) -> str:
    return run(["git", "-C", str(repo), *arguments]).stdout.strip()


def repository_build_identity(
    repo: Path,
    version: str,
    configuration: str,
    product_identifier: str,
) -> dict[str, object]:
    """Return the canonical identity for the current repository state."""
    repo = repo.expanduser().resolve()
    try:
        root = Path(_git(repo, "rev-parse", "--show-toplevel")).resolve()
    except ReleaseError as error:
        raise ReleaseError("build identity repository is not a Git worktree") from error
    if root != repo:
        raise ReleaseError("build identity repository must be the exact Git worktree root")
    commit = require_git_commit(_git(repo, "rev-parse", "HEAD"))
    source_tree = require_git_object_id(
        _git(repo, "rev-parse", "HEAD^{tree}"), "source tree"
    )
    dirty = bool(_git(repo, "status", "--porcelain=v1", "--untracked-files=all"))
    return validate_build_identity({
        "configuration": require_configuration(configuration),
        "productIdentifier": require_product_identifier(product_identifier),
        "schemaVersion": SCHEMA_VERSION,
        "sourceCommit": commit,
        "sourceDirty": dirty,
        "sourceTree": source_tree,
        "version": require_version(version),
    })


def validate_build_identity(value: object) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != IDENTITY_FIELDS:
        raise ReleaseError("host build identity has an unexpected field set")
    if type(value.get("schemaVersion")) is not int or value["schemaVersion"] != SCHEMA_VERSION:
        raise ReleaseError("host build identity schema version is unsupported")
    if type(value.get("sourceDirty")) is not bool:
        raise ReleaseError("host build identity sourceDirty must be Boolean")
    version = value.get("version")
    if not isinstance(version, str):
        raise ReleaseError("build identity version must be a string")
    validated: dict[str, object] = {
        "configuration": require_configuration(value.get("configuration")),
        "productIdentifier": require_product_identifier(value.get("productIdentifier")),
        "schemaVersion": SCHEMA_VERSION,
        "sourceCommit": require_git_object_id(value.get("sourceCommit"), "source commit"),
        "sourceDirty": value["sourceDirty"],
        "sourceTree": require_git_object_id(value.get("sourceTree"), "source tree"),
        "version": require_version(version, "build identity version"),
    }
    return validated


def canonical_identity_bytes(value: object) -> bytes:
    validated = validate_build_identity(value)
    encoded = (
        json.dumps(validated, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        + "\n"
    ).encode("ascii")
    if len(encoded) > MAX_IDENTITY_SIZE:
        raise ReleaseError("host build identity exceeds its size limit")
    return encoded


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseError(f"host build identity duplicates field: {key}")
        result[key] = value
    return result


def parse_identity_bytes(data: bytes) -> dict[str, object]:
    if not data or len(data) > MAX_IDENTITY_SIZE:
        raise ReleaseError("embedded host build identity has an invalid size")
    try:
        text = data.decode("ascii")
        value = json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_constant=lambda token: (_ for _ in ()).throw(
                ReleaseError(f"host build identity contains invalid number: {token}")
            ),
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError("embedded host build identity is not canonical JSON") from error
    validated = validate_build_identity(value)
    if canonical_identity_bytes(validated) != data:
        raise ReleaseError("embedded host build identity is not canonically encoded")
    return validated


def write_repository_build_identity(
    output: Path,
    repo: Path,
    version: str,
    configuration: str,
    product_identifier: str,
) -> dict[str, object]:
    identity = repository_build_identity(
        repo, version, configuration, product_identifier
    )
    encoded = canonical_identity_bytes(identity)
    lexical_output = output.expanduser().absolute()
    lexical_output.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    try:
        output_parent = lexical_output.parent.resolve(strict=True)
    except OSError as error:
        raise ReleaseError("build identity output parent is unavailable") from error
    if not output_parent.is_dir():
        raise ReleaseError("build identity output parent must be a real directory")
    output = output_parent / lexical_output.name
    if output.is_symlink() or (output.exists() and not output.is_file()):
        raise ReleaseError("build identity output must be a regular file")
    if output.exists() and output.read_bytes() == encoded:
        return identity
    descriptor, raw_temporary = tempfile.mkstemp(
        prefix=f".{output.name}.", dir=output.parent
    )
    temporary = Path(raw_temporary)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return identity


def _decode_name(raw: bytes) -> str:
    try:
        return raw.split(b"\0", 1)[0].decode("ascii")
    except UnicodeDecodeError as error:
        raise ReleaseError("Mach-O contains a non-ASCII segment or section name") from error


def extract_embedded_identity(executable: Path, *, required: bool = True) -> dict[str, object] | None:
    """Extract the canonical identity from a thin arm64 MH_EXECUTE."""
    executable = executable.expanduser().absolute()
    try:
        entry = executable.lstat()
    except OSError as error:
        raise ReleaseError("host executable is missing or unreadable") from error
    if (
        not stat.S_ISREG(entry.st_mode)
        or stat.S_ISLNK(entry.st_mode)
        or entry.st_nlink != 1
        or entry.st_size < 32
        or entry.st_size > MAX_EXECUTABLE_SIZE
    ):
        raise ReleaseError("host executable is missing, linked, or outside size limits")
    with executable.open("rb") as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ReleaseError("host executable has a truncated Mach-O header")
        magic, cpu_type, _, file_type, command_count, command_size, _, _ = struct.unpack(
            "<IiiIIIII", header
        )
        if magic != MH_MAGIC_64 or cpu_type != CPU_TYPE_ARM64 or file_type != MH_EXECUTE:
            raise ReleaseError("host executable is not a thin arm64 MH_EXECUTE")
        if (
            command_count > 4096
            or command_size > MAX_LOAD_COMMAND_SIZE
            or 32 + command_size > entry.st_size
        ):
            raise ReleaseError("host executable has unsafe Mach-O load commands")
        commands = stream.read(command_size)
        if len(commands) != command_size:
            raise ReleaseError("host executable has truncated Mach-O load commands")
        found: tuple[int, int] | None = None
        cursor = 0
        for _ in range(command_count):
            if cursor + 8 > len(commands):
                raise ReleaseError("host executable has a truncated Mach-O load command")
            command, size = struct.unpack_from("<II", commands, cursor)
            if size < 8 or cursor + size > len(commands):
                raise ReleaseError("host executable has an invalid Mach-O load command")
            if command == LC_SEGMENT_64:
                if size < 72:
                    raise ReleaseError("host executable has a truncated LC_SEGMENT_64")
                segment = struct.unpack_from("<II16sQQQQiiII", commands, cursor)
                segment_name = _decode_name(segment[2])
                section_count = segment[9]
                if section_count > 4096 or 72 + section_count * 80 > size:
                    raise ReleaseError("host executable has invalid Mach-O sections")
                for index in range(section_count):
                    section_offset = cursor + 72 + index * 80
                    section = struct.unpack_from(
                        "<16s16sQQIIIIIIII", commands, section_offset
                    )
                    section_name = _decode_name(section[0])
                    section_segment = _decode_name(section[1])
                    if (
                        segment_name == SEGMENT_NAME
                        and section_segment == SEGMENT_NAME
                        and section_name == SECTION_NAME
                    ):
                        if found is not None:
                            raise ReleaseError("host executable has duplicate build identities")
                        data_size = section[3]
                        data_offset = section[4]
                        if (
                            data_size < 1
                            or data_size > MAX_IDENTITY_SIZE
                            or data_offset + data_size > entry.st_size
                        ):
                            raise ReleaseError("host build identity section is outside size limits")
                        found = (data_offset, data_size)
            cursor += size
        if cursor != command_size:
            raise ReleaseError("host executable load-command size is inconsistent")
        if found is None:
            if required:
                raise ReleaseError("host executable has no embedded Battman build identity")
            return None
        stream.seek(found[0])
        data = stream.read(found[1])
        if len(data) != found[1]:
            raise ReleaseError("host build identity section is truncated")
    return parse_identity_bytes(data)


def require_embedded_identity(
    executable: Path,
    *,
    version: str,
    configuration: str,
    product_identifier: str,
    source_commit: str | None = None,
    source_tree: str | None = None,
    source_dirty: bool | None = None,
) -> dict[str, object]:
    identity = extract_embedded_identity(executable, required=True)
    assert identity is not None
    expected: dict[str, object] = {
        "version": require_version(version),
        "configuration": require_configuration(configuration),
        "productIdentifier": require_product_identifier(product_identifier),
    }
    if source_commit is not None:
        expected["sourceCommit"] = require_git_commit(source_commit)
    if source_tree is not None:
        expected["sourceTree"] = require_git_object_id(source_tree, "source tree")
    if source_dirty is not None:
        if type(source_dirty) is not bool:
            raise ReleaseError("expected sourceDirty must be Boolean")
        expected["sourceDirty"] = source_dirty
    for field, value in expected.items():
        if identity.get(field) != value:
            raise ReleaseError(
                f"embedded host build identity {field} differs from the expected release input"
            )
    return identity


def require_repository_identity(
    executable: Path,
    repo: Path,
    version: str,
    configuration: str,
    product_identifier: str,
) -> dict[str, object]:
    expected = repository_build_identity(
        repo, version, configuration, product_identifier
    )
    actual = extract_embedded_identity(executable, required=True)
    if actual != expected:
        raise ReleaseError("embedded host build identity differs from the current source state")
    assert actual is not None
    return actual
