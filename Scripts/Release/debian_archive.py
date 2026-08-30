#!/usr/bin/env python3
"""Bounded deterministic Debian binary-package writer and reader.

The implementation supports the exact Battman subset: format 2.0, xz-compressed
control/data tar members, regular files and directories, and no maintainer
scripts or links. It never extracts with owner privileges.
"""

from __future__ import annotations

import io
import lzma
import os
import stat
import tarfile
from pathlib import Path, PurePosixPath
from typing import Iterable

from release_common import ReleaseError, iter_tree, require_input_directory


AR_MAGIC = b"!<arch>\n"
AR_HEADER_BYTES = 60
MAX_DEBIAN_BYTES = 512 * 1024 * 1024
MAX_MEMBER_BYTES = 384 * 1024 * 1024
EXPECTED_MEMBERS = ("debian-binary", "control.tar.xz", "data.tar.xz")
DEBIAN_TAR_FORMAT = tarfile.USTAR_FORMAT


def _ar_header(name: str, size: int, epoch: int, mode: int = 0o100644) -> bytes:
    identifier = f"{name}/"
    fields = (
        identifier.ljust(16),
        str(epoch).ljust(12),
        "0".ljust(6),
        "0".ljust(6),
        format(mode, "o").ljust(8),
        str(size).ljust(10),
        "`\n",
    )
    encoded = "".join(fields).encode("ascii")
    if len(identifier) > 16 or len(encoded) != AR_HEADER_BYTES:
        raise ReleaseError(f"Debian ar member metadata exceeds fixed fields: {name}")
    return encoded


def _write_ar_member(stream: io.BufferedWriter, name: str, source: Path, epoch: int) -> None:
    size = source.stat().st_size
    if size > MAX_MEMBER_BYTES:
        raise ReleaseError(f"Debian ar member exceeds bounded size: {name}")
    stream.write(_ar_header(name, size, epoch))
    with source.open("rb") as member:
        while block := member.read(64 * 1024):
            stream.write(block)
    if size & 1:
        stream.write(b"\n")


def _tar_info(name: str, mode: int, epoch: int, *, directory: bool, size: int = 0) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name + ("/" if directory and not name.endswith("/") else ""))
    info.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
    info.mode = mode
    info.size = 0 if directory else size
    info.mtime = epoch
    info.uid = info.gid = 0
    info.uname = info.gname = "root"
    return info


def _write_control_tar(path: Path, control: bytes, epoch: int) -> None:
    buffer = io.BytesIO()
    try:
        # Older iOS dpkg/tar builds reject POSIX PAX extended-header records.
        # Battman's bounded package paths fit ustar's name/prefix fields, so
        # require that interoperable representation instead of emitting PAX.
        with tarfile.open(fileobj=buffer, mode="w", format=DEBIAN_TAR_FORMAT) as archive:
            archive.addfile(_tar_info("./", 0o755, epoch, directory=True))
            info = _tar_info("./control", 0o644, epoch, directory=False, size=len(control))
            archive.addfile(info, io.BytesIO(control))
    except ValueError as error:
        raise ReleaseError("Debian control metadata is not representable in ustar") from error
    path.write_bytes(lzma.compress(buffer.getvalue(), format=lzma.FORMAT_XZ, preset=9))


def _write_data_tar(path: Path, root: Path, epoch: int) -> None:
    root = require_input_directory(root)
    buffer = io.BytesIO()
    try:
        with tarfile.open(fileobj=buffer, mode="w", format=DEBIAN_TAR_FORMAT) as archive:
            archive.addfile(_tar_info("./", 0o755, epoch, directory=True))
            for relative, source, entry in iter_tree(root):
                name = f"./{relative}"
                if stat.S_ISDIR(entry.st_mode):
                    archive.addfile(_tar_info(name, 0o755, epoch, directory=True))
                else:
                    mode = 0o755 if entry.st_mode & 0o111 else 0o644
                    info = _tar_info(name, mode, epoch, directory=False, size=entry.st_size)
                    with source.open("rb") as stream:
                        archive.addfile(info, stream)
    except ValueError as error:
        raise ReleaseError("Debian payload path or metadata is not representable in ustar") from error
    path.write_bytes(lzma.compress(buffer.getvalue(), format=lzma.FORMAT_XZ, preset=9))


def build_debian_package(root: Path, output: Path, epoch: int, temporary: Path) -> None:
    """Write `output` from an independently staged Debian root."""
    root = require_input_directory(root)
    control_path = root / "DEBIAN/control"
    if not control_path.is_file() or control_path.is_symlink():
        raise ReleaseError("Debian staging root has no regular DEBIAN/control")
    control_entries = sorted(path.relative_to(root / "DEBIAN").as_posix() for path in (root / "DEBIAN").rglob("*"))
    if control_entries != ["control"]:
        raise ReleaseError("Debian staging root contains a maintainer script or unexpected control file")

    payload_root = temporary / "payload"
    payload_root.mkdir(mode=0o755)
    for child in sorted(root.iterdir(), key=lambda value: value.name.encode("utf-8")):
        if child.name == "DEBIAN":
            continue
        os.rename(child, payload_root / child.name)
    os.utime(payload_root, (epoch, epoch), follow_symlinks=False)

    debian_binary = temporary / "debian-binary"
    debian_binary.write_bytes(b"2.0\n")
    os.chmod(debian_binary, 0o644)
    os.utime(debian_binary, (epoch, epoch), follow_symlinks=False)
    control_tar = temporary / "control.tar.xz"
    data_tar = temporary / "data.tar.xz"
    _write_control_tar(control_tar, control_path.read_bytes(), epoch)
    _write_data_tar(data_tar, payload_root, epoch)
    for member in (control_tar, data_tar):
        os.chmod(member, 0o644)
        os.utime(member, (epoch, epoch), follow_symlinks=False)

    with output.open("xb") as archive:
        archive.write(AR_MAGIC)
        for name, member in zip(EXPECTED_MEMBERS, (debian_binary, control_tar, data_tar), strict=True):
            _write_ar_member(archive, name, member, epoch)
    os.chmod(output, 0o644)
    os.utime(output, (epoch, epoch), follow_symlinks=False)


def read_ar_members(path: Path) -> dict[str, bytes]:
    path = path.expanduser().resolve()
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_DEBIAN_BYTES:
        raise ReleaseError("Debian input is not a bounded regular file")
    members: dict[str, bytes] = {}
    with path.open("rb") as stream:
        if stream.read(len(AR_MAGIC)) != AR_MAGIC:
            raise ReleaseError("Debian input has no ar archive magic")
        while True:
            header = stream.read(AR_HEADER_BYTES)
            if not header:
                break
            if len(header) != AR_HEADER_BYTES or header[-2:] != b"`\n":
                raise ReleaseError("Debian ar header is truncated or malformed")
            try:
                raw_name = header[:16].decode("ascii").rstrip()
                name = raw_name[:-1] if raw_name.endswith("/") else raw_name
                size = int(header[48:58].decode("ascii").strip())
            except (UnicodeDecodeError, ValueError) as error:
                raise ReleaseError("Debian ar header contains invalid fields") from error
            if name not in EXPECTED_MEMBERS or name in members or size < 0 or size > MAX_MEMBER_BYTES:
                raise ReleaseError(f"unexpected, duplicate, or oversized Debian ar member: {name}")
            data = stream.read(size)
            if len(data) != size:
                raise ReleaseError(f"truncated Debian ar member: {name}")
            if size & 1 and stream.read(1) != b"\n":
                raise ReleaseError(f"invalid Debian ar padding: {name}")
            members[name] = data
    if tuple(members) != EXPECTED_MEMBERS or members["debian-binary"] != b"2.0\n":
        raise ReleaseError("Debian ar member order or binary format is invalid")
    return members


def _safe_tar_name(name: str) -> str:
    normalized = name[2:] if name.startswith("./") else name
    normalized = normalized.rstrip("/")
    if not normalized:
        return "."
    pure = PurePosixPath(normalized)
    if name.startswith("/") or "\\" in name or any(part in ("", ".", "..") for part in pure.parts):
        raise ReleaseError(f"unsafe Debian tar path: {name!r}")
    return pure.as_posix()


def read_control(members: dict[str, bytes]) -> bytes:
    with tarfile.open(fileobj=io.BytesIO(members["control.tar.xz"]), mode="r:xz") as archive:
        control: bytes | None = None
        names: list[str] = []
        for member in archive:
            name = _safe_tar_name(member.name)
            names.append(name)
            if member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
                raise ReleaseError(f"unsupported Debian control-tar entry: {member.name}")
            if member.isfile():
                if name != "control" or control is not None:
                    raise ReleaseError("Debian control archive contains a maintainer script or extra file")
                extracted = archive.extractfile(member)
                if extracted is None:
                    raise ReleaseError("Debian control file could not be read")
                control = extracted.read(256 * 1024 + 1)
                if len(control) > 256 * 1024:
                    raise ReleaseError("Debian control file exceeds 256 KiB")
        if control is None or set(names) != {".", "control"}:
            raise ReleaseError("Debian control archive has an unexpected layout")
        return control


def data_members(members: dict[str, bytes]) -> list[tarfile.TarInfo]:
    with tarfile.open(fileobj=io.BytesIO(members["data.tar.xz"]), mode="r:xz") as archive:
        entries = list(archive)
        _validate_data_entries(entries)
        return entries


def _validate_data_entries(entries: list[tarfile.TarInfo]) -> list[tuple[tarfile.TarInfo, str]]:
    validated: list[tuple[tarfile.TarInfo, str]] = []
    seen: set[str] = set()
    for member in entries:
        name = _safe_tar_name(member.name)
        if name in seen or member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
            raise ReleaseError(f"duplicate or unsupported Debian data entry: {member.name}")
        if member.uid != 0 or member.gid != 0 or member.mode & (
            stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID
        ):
            raise ReleaseError(f"unsafe Debian data metadata: {member.name}")
        seen.add(name)
        validated.append((member, name))
    return validated


def extract_data(members: dict[str, bytes], destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise ReleaseError("Debian extraction destination must not exist")
    destination.mkdir(mode=0o700, parents=True)
    with tarfile.open(fileobj=io.BytesIO(members["data.tar.xz"]), mode="r:xz") as archive:
        entries = list(archive)
        validated = _validate_data_entries(entries)
        for member, name in validated:
            if name == ".":
                continue
            target = destination / name
            if member.isdir():
                target.mkdir(mode=0o755, parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ReleaseError(f"Debian data member could not be read: {name}")
                with target.open("xb") as output:
                    while block := source.read(64 * 1024):
                        output.write(block)
                os.chmod(target, 0o755 if member.mode & 0o111 else 0o644)
            else:
                raise ReleaseError(f"unsupported Debian extraction entry: {name}")
        for member, name in reversed(validated):
            if name != "." and member.isdir():
                os.chmod(destination / name, 0o755)
