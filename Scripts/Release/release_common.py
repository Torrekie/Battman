#!/usr/bin/env python3
"""Shared bounded, deterministic release-packaging primitives."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


IDENTIFIER = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
    r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$"
)
# Battman public releases use MAJ.MIN.PATCH with an optional numeric REV.
# Release/Debug are build configurations; readiness gates never appear in a
# public version string.  The optional fourth component preserves historical
# releases such as 1.0.3.3 while allowing a base release such as 1.1.0.
VERSION = re.compile(
    r"^(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)"
    r"(?:\.(?:0|[1-9][0-9]*))?$"
)
GIT_COMMIT = re.compile(r"^[0-9a-f]{40}$")
MINIMUM_ZIP_EPOCH = 315532800  # 1980-01-01
PLUGIN_SDK_MIT_LICENSE_SHA256 = (
    "5c85131614b353fb0fae38ca7114bce881baded9382d6718bbe8c2ac30a70edf"
)


class ReleaseError(ValueError):
    """A release input or artifact violated the bounded contract."""


def require_identifier(value: str, label: str = "identifier") -> str:
    if len(value) > 255 or not IDENTIFIER.fullmatch(value):
        raise ReleaseError(f"{label} must be a lowercase reverse-DNS identifier")
    return value


def require_version(value: str, label: str = "version") -> str:
    if not VERSION.fullmatch(value):
        raise ReleaseError(
            f"{label} must use MAJ.MIN.PATCH or MAJ.MIN.PATCH.REV with numeric components"
        )
    return value


def require_package_version(value: str, label: str = "package version") -> str:
    """Validate a Debian package version that is not Battman's public version.

    Official plug-ins may use an independently versioned numeric package
    release. Keep this bounded and suffix-free while permitting one to four
    numeric components.
    """
    components = value.split(".")
    if not 1 <= len(components) <= 4 or any(
        not component.isascii()
        or not component.isdigit()
        or len(component) > 10
        or len(component) > 1 and component.startswith("0")
        for component in components
    ):
        raise ReleaseError(
            f"{label} must use one to four dot-separated numeric components"
        )
    return value


def require_git_commit(value: str) -> str:
    if not GIT_COMMIT.fullmatch(value):
        raise ReleaseError("source commit must be a full lowercase 40-hex Git object ID")
    return value


def require_plugin_sdk_license_data(data: bytes, label: str = "PluginSDK/LICENSE") -> None:
    """Require the exact owner-approved MIT license bytes for PluginSDK v1."""
    if not data or len(data) > 16 * 1024:
        raise ReleaseError(f"{label} must be one bounded license file")
    if hashlib.sha256(data).hexdigest() != PLUGIN_SDK_MIT_LICENSE_SHA256:
        raise ReleaseError(
            f"{label} does not match the owner-approved PluginSDK MIT license"
        )


def require_plugin_sdk_license(path: Path) -> Path:
    lexical = path.expanduser().absolute()
    entry = lexical.lstat()
    if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1:
        raise ReleaseError("PluginSDK/LICENSE must be one real regular file")
    require_plugin_sdk_license_data(lexical.read_bytes())
    return lexical.resolve()


def source_date_epoch(value: int | None = None) -> int:
    if value is None:
        raw = os.environ.get("SOURCE_DATE_EPOCH")
        if not raw:
            raise ReleaseError("SOURCE_DATE_EPOCH or --source-date-epoch is required")
        try:
            value = int(raw)
        except ValueError as error:
            raise ReleaseError("SOURCE_DATE_EPOCH must be an integer") from error
    if value < MINIMUM_ZIP_EPOCH or value > 0x7FFFFFFF:
        raise ReleaseError("source date epoch must be between 1980 and 2038")
    return value


def require_input_directory(path: Path, suffix: str | None = None) -> Path:
    lexical = path.expanduser().absolute()
    if suffix and lexical.suffix != suffix:
        raise ReleaseError(f"input must use the {suffix} suffix: {lexical}")
    entry = lexical.lstat()
    if not stat.S_ISDIR(entry.st_mode) or stat.S_ISLNK(entry.st_mode):
        raise ReleaseError(f"input must be a real directory: {lexical}")
    return lexical.resolve()


def require_new_output(path: Path, suffix: str | None = None) -> Path:
    lexical = path.expanduser().absolute()
    if suffix and lexical.suffix != suffix:
        raise ReleaseError(f"output must use the {suffix} suffix: {lexical}")
    if lexical.exists() or lexical.is_symlink():
        raise ReleaseError(f"output already exists: {lexical}")
    if not lexical.parent.is_dir() or lexical.parent.is_symlink():
        raise ReleaseError(f"output parent must be a real directory: {lexical.parent}")
    return lexical.parent.resolve() / lexical.name


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(64 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _safe_relative(value: str) -> str:
    pure = PurePosixPath(value)
    if not value or value.startswith("/") or "\\" in value or any(
        component in ("", ".", "..") for component in pure.parts
    ):
        raise ReleaseError(f"unsafe relative path: {value!r}")
    return value


def iter_tree(root: Path) -> Iterable[tuple[str, Path, os.stat_result]]:
    """Yield a sorted tree after rejecting links, special files and unsafe modes."""
    root = require_input_directory(root)
    entries: list[tuple[str, Path, os.stat_result]] = []
    for directory, directory_names, file_names in os.walk(root, followlinks=False):
        directory_names.sort(key=lambda value: value.encode("utf-8"))
        file_names.sort(key=lambda value: value.encode("utf-8"))
        directory_path = Path(directory)
        for name in directory_names + file_names:
            path = directory_path / name
            relative = _safe_relative(path.relative_to(root).as_posix())
            entry = path.lstat()
            if stat.S_ISLNK(entry.st_mode):
                raise ReleaseError(f"symbolic links are not accepted in release inputs: {relative}")
            if stat.S_ISDIR(entry.st_mode):
                entries.append((relative, path, entry))
            elif stat.S_ISREG(entry.st_mode) and entry.st_nlink == 1:
                entries.append((relative, path, entry))
            else:
                raise ReleaseError(f"special or hard-linked release input: {relative}")
            if entry.st_mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
                raise ReleaseError(f"unsafe release-input mode: {relative}")
    return sorted(entries, key=lambda item: item[0].encode("utf-8"))


def copy_tree_normalized(source: Path, destination: Path, epoch: int) -> None:
    if destination.exists() or destination.is_symlink():
        raise ReleaseError(f"staging destination already exists: {destination}")
    destination.mkdir(mode=0o755, parents=True)
    directories = [destination]
    for relative, path, entry in iter_tree(source):
        target = destination / relative
        if stat.S_ISDIR(entry.st_mode):
            target.mkdir(mode=0o755)
            directories.append(target)
        else:
            target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            shutil.copyfile(path, target, follow_symlinks=False)
            executable = bool(entry.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
            os.chmod(target, 0o755 if executable else 0o644)
        os.utime(target, (epoch, epoch), follow_symlinks=False)
    # Creating descendants changes their parent mtimes. Normalize directories
    # after the whole tree exists, deepest first, so archive metadata does not
    # depend on copy duration or source traversal timing.
    for directory in reversed(directories):
        os.chmod(directory, 0o755)
        os.utime(directory, (epoch, epoch), follow_symlinks=False)


def tree_size_kib(root: Path) -> int:
    total = sum(entry.st_size for _, _, entry in iter_tree(root) if stat.S_ISREG(entry.st_mode))
    return max(1, (total + 1023) // 1024)


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for relative, path, entry in iter_tree(root):
        encoded = relative.encode("utf-8")
        digest.update(b"D" if stat.S_ISDIR(entry.st_mode) else b"F")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
        if stat.S_ISREG(entry.st_mode):
            digest.update(bytes.fromhex(sha256_file(path)))
            digest.update(entry.st_size.to_bytes(8, "big"))
            digest.update(b"X" if entry.st_mode & 0o111 else b"-")
    return digest.hexdigest()


def render_template(path: Path, values: dict[str, str]) -> str:
    result = path.read_text(encoding="utf-8")
    for key, value in values.items():
        if "\n" in value or "\r" in value:
            raise ReleaseError(f"template value contains a newline: {key}")
        result = result.replace(f"@{key}@", value)
    unresolved = sorted(set(re.findall(r"@[A-Z0-9_]+@", result)))
    if unresolved:
        raise ReleaseError(f"unresolved template fields: {', '.join(unresolved)}")
    return result


def write_normalized(path: Path, data: bytes, epoch: int, mode: int = 0o644) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    path.write_bytes(data)
    os.chmod(path, mode)
    os.utime(path, (epoch, epoch), follow_symlinks=False)


def load_app_info(app: Path) -> tuple[dict[str, Any], Path]:
    app = require_input_directory(app, ".app")
    try:
        with (app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ReleaseError(f"invalid app Info.plist: {error}") from error
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or "/" in executable_name:
        raise ReleaseError("app Info.plist has no safe CFBundleExecutable")
    executable = app / executable_name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ReleaseError("app executable is missing or not executable")
    return info, executable


def temporary_sibling(parent: Path, prefix: str) -> Path:
    return Path(tempfile.mkdtemp(prefix=prefix, dir=parent))


def run(arguments: list[str], *, environment: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, text=True, capture_output=True, env=environment)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReleaseError(f"command failed ({result.returncode}): {' '.join(arguments)}\n{detail}")
    return result


def deterministic_zip(source_root: Path, output: Path, epoch: int) -> None:
    output = require_new_output(output)
    timestamp = time.gmtime(epoch)[:6]
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, path, entry in iter_tree(source_root):
            name = relative + ("/" if stat.S_ISDIR(entry.st_mode) else "")
            info = zipfile.ZipInfo(name, timestamp)
            info.create_system = 3
            mode = 0o755 if stat.S_ISDIR(entry.st_mode) or entry.st_mode & 0o111 else 0o644
            kind = stat.S_IFDIR if stat.S_ISDIR(entry.st_mode) else stat.S_IFREG
            info.external_attr = (kind | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits |= 0x800
            archive.writestr(info, b"" if stat.S_ISDIR(entry.st_mode) else path.read_bytes())
    os.utime(output, (epoch, epoch), follow_symlinks=False)


def write_json(path: Path, value: Any, epoch: int) -> None:
    write_normalized(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"), epoch)


def remove_staged_tree(path: Path, required_parent: Path) -> None:
    """Remove only a resolved private staging descendant created by this run."""
    resolved_path = path.resolve()
    resolved_parent = required_parent.resolve()
    if resolved_path == resolved_parent or resolved_parent not in resolved_path.parents:
        raise ReleaseError(f"refusing cleanup outside private staging parent: {resolved_path}")
    shutil.rmtree(resolved_path)
