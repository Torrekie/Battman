#!/usr/bin/env python3
"""Build an unsigned deterministic directory-format .battman package."""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import shutil
import stat
import sys
import tempfile
from pathlib import Path
from pathlib import PurePosixPath

from battman_plugin_format import (
    PluginFormatError,
    canonical_json_bytes,
    inventory,
    load_strict_json,
    macho_code_identity,
    signature_paths,
    validate_author_metadata,
    validate_display_name,
    validate_relative_path,
    verify_payload_structure,
)


def _require_safe_payload_source(path: Path) -> None:
    try:
        root_stat = path.lstat()
    except FileNotFoundError as exc:
        raise PluginFormatError(f"payload does not exist: {path}") from exc
    if stat.S_ISLNK(root_stat.st_mode) or not (
        stat.S_ISDIR(root_stat.st_mode) or stat.S_ISREG(root_stat.st_mode)
    ):
        raise PluginFormatError("payload must be a real directory or regular file")
    if stat.S_ISREG(root_stat.st_mode):
        return
    for directory, directory_names, file_names in os.walk(path, followlinks=False):
        directory_path = Path(directory)
        for name in directory_names:
            entry = directory_path / name
            entry_stat = entry.lstat()
            if stat.S_ISLNK(entry_stat.st_mode) or not stat.S_ISDIR(entry_stat.st_mode):
                raise PluginFormatError(f"payload contains a non-directory entry: {entry}")
        for name in file_names:
            entry = directory_path / name
            entry_stat = entry.lstat()
            if stat.S_ISLNK(entry_stat.st_mode) or not stat.S_ISREG(entry_stat.st_mode):
                raise PluginFormatError(f"payload contains a non-regular file: {entry}")


def _normalize_copied_payload(path: Path, executable: Path) -> None:
    if path.is_file() and not path.is_symlink():
        os.chmod(path, 0o755 if path == executable else 0o644)
        return
    for directory, directory_names, file_names in os.walk(path, followlinks=False):
        directory_path = Path(directory)
        directory_stat = directory_path.lstat()
        if stat.S_ISLNK(directory_stat.st_mode) or not stat.S_ISDIR(directory_stat.st_mode):
            raise PluginFormatError(f"copied payload contains a non-directory entry: {directory_path}")
        os.chmod(directory_path, 0o755)
        for name in directory_names:
            entry = directory_path / name
            entry_stat = entry.lstat()
            if stat.S_ISLNK(entry_stat.st_mode) or not stat.S_ISDIR(entry_stat.st_mode):
                raise PluginFormatError(f"copied payload contains a non-directory entry: {entry}")
        for name in file_names:
            entry = directory_path / name
            entry_stat = entry.lstat()
            if stat.S_ISLNK(entry_stat.st_mode) or not stat.S_ISREG(entry_stat.st_mode):
                raise PluginFormatError(f"copied payload contains a non-regular file: {entry}")
            os.chmod(entry, 0o755 if entry == executable else 0o644)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-template", required=True, type=Path)
    parser.add_argument("--payload", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--publisher-public-key",
        action="append",
        default=[],
        type=Path,
        help="include a 65-byte uncompressed P-256 public key for offline approval",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    output = arguments.output.resolve()
    if output.suffix != ".battman":
        raise PluginFormatError("output must use the .battman extension")
    if output.exists():
        raise PluginFormatError("output already exists")
    manifest = load_strict_json(arguments.manifest_template.read_bytes())
    if not isinstance(manifest, dict):
        raise PluginFormatError("manifest template must be an object")
    validate_display_name(manifest)
    validate_author_metadata(manifest)
    payload = manifest.get("payload")
    publisher = manifest.get("publisher")
    if not isinstance(payload, dict) or not isinstance(publisher, dict):
        raise PluginFormatError("manifest template needs payload and publisher objects")
    if "files" in manifest:
        raise PluginFormatError("manifest template must omit generated files")
    if "codeIdentity" in payload:
        raise PluginFormatError("manifest template must omit generated payload.codeIdentity")
    declared_key_identifiers = dict(signature_paths(manifest))
    payload_path = payload.get("path")
    executable_path = payload.get("executablePath")
    if not isinstance(payload_path, str) or not isinstance(executable_path, str):
        raise PluginFormatError("payload paths are missing")
    validate_relative_path(payload_path)
    validate_relative_path(executable_path)
    payload_parts = PurePosixPath(payload_path).parts
    executable_parts = PurePosixPath(executable_path).parts
    if executable_parts[:len(payload_parts)] != payload_parts:
        raise PluginFormatError("executablePath must be contained by payload.path")
    _require_safe_payload_source(arguments.payload)

    if not output.parent.is_dir():
        raise PluginFormatError("output parent directory must already exist")
    staging = Path(tempfile.mkdtemp(prefix=f".{output.name}.incoming-", dir=output.parent))
    try:
        os.chmod(staging, 0o755)
        destination_payload = staging / payload_path
        if arguments.payload.is_dir():
            shutil.copytree(arguments.payload, destination_payload, symlinks=True)
        else:
            destination_payload.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(arguments.payload, destination_payload, follow_symlinks=False)
        executable = staging / executable_path
        if not executable.is_file() or executable.is_symlink():
            raise PluginFormatError("declared executablePath is absent after copying the payload")
        _normalize_copied_payload(destination_payload, executable)
        provisional_files = inventory(staging, executable_path)
        manifest["files"] = provisional_files
        verify_payload_structure(staging, manifest)
        payload["codeIdentity"] = macho_code_identity(executable)

        signatures = staging / "Signatures"
        signatures.mkdir(mode=0o755)
        included_key_identifiers: set[str] = set()
        for public_key_path in arguments.publisher_public_key:
            public_key = public_key_path.read_bytes()
            if len(public_key) != 65 or public_key[0] != 4:
                raise PluginFormatError(
                    f"publisher public key must be a 65-byte uncompressed P-256 point: {public_key_path}"
                )
            key_identifier = hashlib.sha256(public_key).hexdigest()
            if key_identifier not in declared_key_identifiers:
                raise PluginFormatError(
                    f"publisher public key is not declared by the manifest: {key_identifier}"
                )
            if key_identifier in included_key_identifiers:
                raise PluginFormatError(f"duplicate publisher public key: {key_identifier}")
            included_key_identifiers.add(key_identifier)
            publisher_keys = staging / "PublisherKeys"
            publisher_keys.mkdir(mode=0o755, exist_ok=True)
            destination_key = publisher_keys / f"{key_identifier}.p256"
            destination_key.write_bytes(public_key)
            os.chmod(destination_key, 0o644)
        info = {
            "CFBundleIdentifier": manifest["pluginIdentifier"],
            "CFBundleDisplayName": manifest["displayName"],
            "CFBundleShortVersionString": manifest["displayVersion"],
            "CFBundleVersion": manifest["buildVersion"],
            "CFBundlePackageType": "BTPG",
            "BTPluginPackageFormatVersion": 1,
            "BTPluginPublisherKeyIdentifier": publisher["primaryKeyIdentifier"],
        }
        with (staging / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream, fmt=plistlib.FMT_BINARY, sort_keys=True)
        os.chmod(staging / "Info.plist", 0o644)
        manifest["files"] = inventory(staging, executable_path)
        (staging / "Manifest.json").write_bytes(canonical_json_bytes(manifest))
        os.chmod(staging / "Manifest.json", 0o644)
        os.rename(staging, output)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, PluginFormatError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
