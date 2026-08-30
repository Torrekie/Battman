#!/usr/bin/env python3
"""Validate and copy Battman's optional public trust resources into one app."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile


EXPECTED_ROOT_FILES = {"RootPolicy.plist", "TrustMetadata.json"}
SIGNATURE_DIRECTORY = "TrustMetadata.signatures"
MAX_ROOT_POLICY_BYTES = 64 * 1024
MAX_METADATA_BYTES = 256 * 1024
MAX_SIGNATURE_BYTES = 256
MAX_SIGNATURES = 8


class ResourceError(RuntimeError):
    pass


def _validate_directory(path: Path, label: str) -> None:
    try:
        value = path.lstat()
    except FileNotFoundError as error:
        raise ResourceError(f"{label} is missing: {path}") from error
    if not stat.S_ISDIR(value.st_mode) or path.is_symlink():
        raise ResourceError(f"{label} must be a real directory: {path}")
    if value.st_mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
        raise ResourceError(f"{label} has an unsafe mode: {path}")


def _validate_regular_file(path: Path, label: str, maximum_size: int) -> None:
    try:
        value = path.lstat()
    except FileNotFoundError as error:
        raise ResourceError(f"{label} is missing: {path}") from error
    if not stat.S_ISREG(value.st_mode) or path.is_symlink() or value.st_nlink != 1:
        raise ResourceError(f"{label} must be one regular, non-linked file: {path}")
    if value.st_size <= 0 or value.st_size > maximum_size:
        raise ResourceError(f"{label} exceeds its bounded size: {path}")
    if value.st_mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
        raise ResourceError(f"{label} has an unsafe mode: {path}")


def validate_source(source: Path) -> list[Path]:
    _validate_directory(source, "PluginTrust")
    names = {entry.name for entry in source.iterdir()}
    expected = EXPECTED_ROOT_FILES | {SIGNATURE_DIRECTORY}
    if names != expected:
        raise ResourceError("PluginTrust must contain exactly RootPolicy.plist, "
                            "TrustMetadata.json, and TrustMetadata.signatures")
    _validate_regular_file(source / "RootPolicy.plist", "root policy", MAX_ROOT_POLICY_BYTES)
    _validate_regular_file(source / "TrustMetadata.json", "trust metadata", MAX_METADATA_BYTES)
    signatures = source / SIGNATURE_DIRECTORY
    _validate_directory(signatures, "trust-metadata signature directory")
    entries = sorted(signatures.iterdir(), key=lambda value: os.fsencode(value.name))
    if not 1 <= len(entries) <= MAX_SIGNATURES:
        raise ResourceError("TrustMetadata.signatures must contain between one and eight signatures")
    for entry in entries:
        stem = entry.name.removesuffix(".sig")
        if entry.name != f"{stem}.sig" or len(stem) != 64 or any(character not in "0123456789abcdef" for character in stem):
            raise ResourceError(f"invalid trust-metadata signature filename: {entry.name}")
        _validate_regular_file(entry, "trust-metadata signature", MAX_SIGNATURE_BYTES)
    return [source / "RootPolicy.plist", source / "TrustMetadata.json", *entries]


def _regular_file_bytes(path: Path, maximum_size: int) -> bytes:
    _validate_regular_file(path, "installed trust resource", maximum_size)
    return path.read_bytes()


def destination_matches(source: Path, destination: Path, source_files: list[Path]) -> bool:
    try:
        destination_files = validate_source(destination)
    except (OSError, ResourceError):
        return False
    source_by_name = {path.relative_to(source): path for path in source_files}
    destination_by_name = {path.relative_to(destination): path for path in destination_files}
    if source_by_name.keys() != destination_by_name.keys():
        return False
    for relative, source_file in source_by_name.items():
        maximum = MAX_SIGNATURE_BYTES if relative.parts[0] == SIGNATURE_DIRECTORY else (
            MAX_ROOT_POLICY_BYTES if relative.name == "RootPolicy.plist" else MAX_METADATA_BYTES
        )
        if _regular_file_bytes(source_file, maximum) != _regular_file_bytes(destination_by_name[relative], maximum):
            return False
    return True


def install(source: Path, app: Path) -> str:
    if not app.is_dir() or app.is_symlink():
        raise ResourceError(f"app product must be one real directory: {app}")
    destination = app / "PluginTrust"
    if not source.exists():
        if destination.exists() or destination.is_symlink():
            raise ResourceError("the source trust resources are absent but a stale PluginTrust exists in the app")
        return "absent"
    files = validate_source(source)
    if destination.exists() or destination.is_symlink():
        if destination.is_dir() and not destination.is_symlink() and destination_matches(source, destination, files):
            return "already-current"
        raise ResourceError("PluginTrust already exists in the app product with different or unsafe content")
    temporary = Path(tempfile.mkdtemp(prefix=".PluginTrust.", dir=app))
    try:
        (temporary / SIGNATURE_DIRECTORY).mkdir(mode=0o755)
        for source_file in files:
            relative = source_file.relative_to(source)
            destination_file = temporary / relative
            with source_file.open("rb") as input_stream, destination_file.open("xb") as output_stream:
                shutil.copyfileobj(input_stream, output_stream, length=64 * 1024)
            destination_file.chmod(0o644)
        temporary.chmod(0o755)
        (temporary / SIGNATURE_DIRECTORY).chmod(0o755)
        temporary.rename(destination)
    except BaseException:
        shutil.rmtree(temporary)
        raise
    return "installed"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = install(arguments.source, arguments.app)
    except (OSError, ResourceError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(f"PluginTrust resources: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
