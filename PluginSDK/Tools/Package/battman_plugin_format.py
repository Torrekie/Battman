#!/usr/bin/env python3
"""Shared deterministic .battman package primitives for the public SDK.

This module never imports or executes plug-in code. Production signing accepts
an existing P-256 private key; it does not generate production keys.
"""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import stat
import struct
import unicodedata
from pathlib import Path, PurePosixPath
from typing import Any, Iterable
from urllib.parse import urlsplit

MAX_FILE_COUNT = 512
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_MANIFEST_BYTES = 256 * 1024
MAX_SIGNATURE_BYTES = 256
MAX_PATH_BYTES = 1024
MAX_INFO_PLIST_BYTES = 64 * 1024
MACHO_CODE_IDENTITY_ALGORITHM = "macho-codesign-independent-sha256-v1"

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_MASK = 0xFF000000
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D


class PluginFormatError(ValueError):
    """A hard package-format failure."""


BIDI_FORMATTING_CHARACTERS = frozenset(
    "\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"
)


def _duplicate_key_rejected(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise PluginFormatError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_strict_json(data: bytes) -> Any:
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise PluginFormatError("manifest is empty or exceeds 256 KiB")
    if data.startswith(b"\xef\xbb\xbf"):
        raise PluginFormatError("manifest must not contain a UTF-8 BOM")
    try:
        text = data.decode("utf-8")
        return json.loads(text, object_pairs_hook=_duplicate_key_rejected)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PluginFormatError(f"invalid UTF-8 JSON: {exc}") from exc


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def validate_display_string(value: Any, maximum_length: int, label: str) -> None:
    """Reject display text that can visually escape or reorder host-owned UI."""
    if (
        not isinstance(value, str)
        or not 1 <= len(value) <= maximum_length
        or value != value.strip()
        or unicodedata.normalize("NFC", value) != value
        or any(unicodedata.category(character) in {"Cc", "Zl", "Zp"} for character in value)
        or any(character in BIDI_FORMATTING_CHARACTERS for character in value)
    ):
        raise PluginFormatError(f"{label} must be a bounded canonical display string")


def validate_display_name(manifest: dict[str, Any]) -> None:
    validate_display_string(manifest.get("displayName"), 256, "displayName")


def validate_author_metadata(manifest: dict[str, Any]) -> None:
    """Validate optional signed, human-facing author/contact metadata."""
    author = manifest.get("author")
    if author is None:
        return
    if not isinstance(author, dict) or set(author) - {"name", "homepageURL", "supportEmail"}:
        raise PluginFormatError("author must contain only name, homepageURL, and supportEmail")
    name = author.get("name")
    validate_display_string(name, 128, "author.name")

    homepage = author.get("homepageURL")
    if homepage is not None:
        if (
            not isinstance(homepage, str)
            or not 1 <= len(homepage) <= 2048
            or "\\" in homepage
            or any(character.isspace() or unicodedata.category(character) == "Cc" for character in homepage)
        ):
            raise PluginFormatError("author.homepageURL must be a bounded HTTPS URL")
        try:
            parsed = urlsplit(homepage)
            hostname = parsed.hostname
            username = parsed.username
            password = parsed.password
            parsed.port
        except ValueError as exc:
            raise PluginFormatError("author.homepageURL is malformed") from exc
        if parsed.scheme != "https" or not hostname or username is not None or password is not None:
            raise PluginFormatError("author.homepageURL must be an HTTPS URL without user information")

    support_email = author.get("supportEmail")
    if support_email is not None:
        if (
            not isinstance(support_email, str)
            or not 3 <= len(support_email) <= 254
            or not support_email.isascii()
            or any(character.isspace() or ord(character) < 0x20 or ord(character) == 0x7F for character in support_email)
            or support_email.count("@") != 1
        ):
            raise PluginFormatError("author.supportEmail is not a bounded ASCII address")
        local, domain = support_email.split("@")
        local_allowed = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.!#$%&'*+/=?^_`{|}~-")
        if (
            not 1 <= len(local) <= 64
            or local.startswith(".")
            or local.endswith(".")
            or ".." in local
            or any(character not in local_allowed for character in local)
        ):
            raise PluginFormatError("author.supportEmail has an invalid local part")
        labels = domain.split(".")
        if len(domain) > 253 or len(labels) < 2 or any(
            not 1 <= len(label) <= 63
            or label.startswith("-")
            or label.endswith("-")
            or any(not (character.isascii() and (character.isalnum() or character == "-")) for character in label)
            for label in labels
        ):
            raise PluginFormatError("author.supportEmail has an invalid domain")


def validate_relative_path(value: str) -> None:
    if not isinstance(value, str) or not value or value.startswith("/") or value.endswith("/"):
        raise PluginFormatError(f"unsafe relative path: {value!r}")
    if unicodedata.normalize("NFC", value) != value or "\\" in value:
        raise PluginFormatError(f"non-canonical relative path: {value!r}")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise PluginFormatError(f"path is not valid UTF-8: {value!r}") from exc
    if len(encoded) > MAX_PATH_BYTES or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise PluginFormatError(f"path exceeds limits or contains controls: {value!r}")
    parts = PurePosixPath(value).parts
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise PluginFormatError(f"unsafe path component: {value!r}")


def utf8_sort_key(value: str) -> bytes:
    return value.encode("utf-8")


def sha256_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while True:
            block = stream.read(64 * 1024)
            if not block:
                break
            size += len(block)
            if size > MAX_FILE_BYTES:
                raise PluginFormatError(f"file exceeds 64 MiB: {path}")
            digest.update(block)
    return size, digest.hexdigest()


def macho_code_identity(path: Path) -> dict[str, Any]:
    """Hash Mach-O bytes while normalizing only the mutable signing envelope."""
    data = bytearray(path.read_bytes())
    if len(data) < 32 or len(data) > MAX_FILE_BYTES:
        raise PluginFormatError("resignable payload must be one bounded Mach-O file")
    magic, cpu_type, cpu_subtype, _, command_count, command_bytes, _, _ = struct.unpack_from(
        "<IiiIIIII", data, 0
    )
    if (
        magic != MH_MAGIC_64
        or cpu_type != CPU_TYPE_ARM64
        or cpu_subtype & ~CPU_SUBTYPE_MASK != 0
        or command_count == 0
        or command_count > 4096
        or command_bytes > 16 * 1024 * 1024
        or 32 + command_bytes > len(data)
    ):
        raise PluginFormatError("resignable payload must be one thin canonical arm64 Mach-O")

    normalized: list[tuple[int, int]] = []
    command_offset = 32
    command_end = 32 + command_bytes
    linkedit: tuple[int, int, int] | None = None
    signature: tuple[int, int] | None = None
    for _ in range(command_count):
        if command_offset + 8 > command_end:
            raise PluginFormatError("Mach-O load-command table is truncated")
        command, command_size = struct.unpack_from("<II", data, command_offset)
        if command_size < 8 or command_size % 8 or command_offset + command_size > command_end:
            raise PluginFormatError("Mach-O load command has an invalid size")
        if command == LC_SEGMENT_64:
            if command_size < 72:
                raise PluginFormatError("Mach-O segment command is truncated")
            segment_name = bytes(data[command_offset + 8 : command_offset + 24]).rstrip(b"\0")
            if segment_name == b"__LINKEDIT":
                if linkedit is not None:
                    raise PluginFormatError("Mach-O contains duplicate __LINKEDIT segments")
                _, _, _, _, virtual_size, file_offset, file_size, _, _, _, _ = struct.unpack_from(
                    "<II16sQQQQiiII", data, command_offset
                )
                linkedit = (file_offset, file_size, virtual_size)
                normalized.extend(((command_offset + 32, 8), (command_offset + 48, 8)))
        elif command == LC_CODE_SIGNATURE:
            if signature is not None or command_size != 16:
                raise PluginFormatError("Mach-O has duplicate or malformed code-signature metadata")
            signature = struct.unpack_from("<II", data, command_offset + 8)
            normalized.extend(((command_offset + 8, 4), (command_offset + 12, 4)))
        command_offset += command_size

    if command_offset != command_end or linkedit is None or signature is None or len(normalized) != 4:
        raise PluginFormatError("Mach-O lacks canonical __LINKEDIT or code-signature metadata")
    signature_offset, signature_size = signature
    signature_end = signature_offset + signature_size
    file_offset, file_size, virtual_size = linkedit
    linkedit_end = file_offset + file_size
    trailing = len(data) - signature_end
    if (
        signature_offset < command_end
        or signature_offset % 16
        or signature_size < 12
        or signature_end > len(data)
        or trailing < 0
        or trailing > 15
        or any(data[signature_end:])
        or file_size > virtual_size
        or file_offset > signature_offset
        or linkedit_end < signature_end
        or linkedit_end > len(data)
    ):
        raise PluginFormatError("Mach-O signing envelope is not a bounded final __LINKEDIT region")
    for offset, length in normalized:
        if offset + length > signature_offset:
            raise PluginFormatError("Mach-O signing metadata is outside the unsigned region")
        data[offset : offset + length] = b"\0" * length
    return {
        "algorithm": MACHO_CODE_IDENTITY_ALGORITHM,
        "unsignedByteCount": signature_offset,
        "sha256": hashlib.sha256(data[:signature_offset]).hexdigest(),
    }


def _walk_regular_files(root: Path) -> list[tuple[str, Path, os.stat_result]]:
    root_stat = root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode) or root_stat.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        raise PluginFormatError("package root must be a non-writable directory")
    files: list[tuple[str, Path, os.stat_result]] = []
    folded: set[str] = set()
    total_bytes = 0
    for directory, directory_names, file_names in os.walk(root, followlinks=False):
        directory_path = Path(directory)
        for name in sorted(directory_names, key=lambda item: item.encode("utf-8")):
            path = directory_path / name
            entry_stat = path.lstat()
            relative = path.relative_to(root).as_posix()
            validate_relative_path(relative)
            if stat.S_ISLNK(entry_stat.st_mode) or not stat.S_ISDIR(entry_stat.st_mode):
                raise PluginFormatError(f"non-directory package entry: {relative}")
            if entry_stat.st_mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
                raise PluginFormatError(f"unsafe directory permissions: {relative}")
        for name in sorted(file_names, key=lambda item: item.encode("utf-8")):
            path = directory_path / name
            entry_stat = path.lstat()
            relative = path.relative_to(root).as_posix()
            validate_relative_path(relative)
            folded_path = relative.casefold()
            if folded_path in folded:
                raise PluginFormatError(f"case-colliding path: {relative}")
            folded.add(folded_path)
            if not stat.S_ISREG(entry_stat.st_mode) or entry_stat.st_nlink != 1:
                raise PluginFormatError(f"package entries must be single-link regular files: {relative}")
            if entry_stat.st_mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
                raise PluginFormatError(f"unsafe file permissions: {relative}")
            if entry_stat.st_size > MAX_FILE_BYTES:
                raise PluginFormatError(f"file exceeds 64 MiB: {relative}")
            total_bytes += entry_stat.st_size
            if len(files) + 1 > MAX_FILE_COUNT or total_bytes > MAX_TOTAL_BYTES:
                raise PluginFormatError("package exceeds file-count or total-byte limits")
            files.append((relative, path, entry_stat))
    return sorted(files, key=lambda item: utf8_sort_key(item[0]))


def inventory(root: Path, executable_path: str) -> list[dict[str, Any]]:
    validate_relative_path(executable_path)
    records: list[dict[str, Any]] = []
    for relative, path, entry_stat in _walk_regular_files(root):
        if relative == "Manifest.json" or relative.startswith("Signatures/"):
            continue
        executable = bool(entry_stat.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
        if executable != (relative == executable_path):
            raise PluginFormatError(
                f"only the declared payload may use executable permissions: {relative}"
            )
        size, digest = sha256_file(path)
        records.append(
            {
                "path": relative,
                "size": size,
                "mode": "executable" if executable else "data",
                "sha256": digest,
            }
        )
    return records


def package_digest(root: Path) -> str:
    context = hashlib.sha256()
    for relative, path, entry_stat in _walk_regular_files(root):
        size, digest_hex = sha256_file(path)
        path_bytes = relative.encode("utf-8")
        executable = bool(entry_stat.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
        context.update(b"F")
        context.update(len(path_bytes).to_bytes(4, "big"))
        context.update(path_bytes)
        context.update(b"\x01" if executable else b"\x00")
        context.update(size.to_bytes(8, "big"))
        context.update(bytes.fromhex(digest_hex))
    return context.hexdigest()


def verify_outer_info(root: Path, manifest: dict[str, Any]) -> None:
    try:
        with (root / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise PluginFormatError(f"invalid outer Info.plist: {exc}") from exc
    expected = {
        "CFBundleIdentifier": manifest["pluginIdentifier"],
        "CFBundleDisplayName": manifest["displayName"],
        "CFBundleShortVersionString": manifest["displayVersion"],
        "CFBundleVersion": manifest["buildVersion"],
        "CFBundlePackageType": "BTPG",
        "BTPluginPublisherKeyIdentifier": manifest["publisher"]["primaryKeyIdentifier"],
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise PluginFormatError(f"Info.plist mismatch for {key}")
    format_version = info.get("BTPluginPackageFormatVersion")
    if type(format_version) is not int or format_version != 1:
        raise PluginFormatError("Info.plist mismatch for BTPluginPackageFormatVersion")


def verify_payload_structure(root: Path, manifest: dict[str, Any]) -> None:
    """Validate signed inner-bundle identity without executing plug-in code."""
    payload = manifest.get("payload")
    if not isinstance(payload, dict):
        raise PluginFormatError("manifest payload is malformed")
    payload_path = payload.get("path")
    payload_kind = payload.get("kind")
    executable_path = payload.get("executablePath")
    if not isinstance(payload_path, str) or not isinstance(executable_path, str):
        raise PluginFormatError("manifest payload paths are malformed")
    validate_relative_path(payload_path)
    validate_relative_path(executable_path)
    if payload_kind == "so":
        return
    if payload_kind != "bundle":
        raise PluginFormatError("manifest payload kind is unsupported")

    executable_prefix = f"{payload_path}/"
    executable_name = (
        executable_path[len(executable_prefix) :]
        if executable_path.startswith(executable_prefix)
        else ""
    )
    if (
        not payload_path.endswith(".bundle")
        or not executable_name
        or "/" in executable_name
    ):
        raise PluginFormatError("bundle executablePath must name one direct bundle child")

    info_relative = f"{payload_path}/Info.plist"
    declared = manifest.get("files")
    if not isinstance(declared, list):
        raise PluginFormatError("signed file inventory is malformed")
    info_records = [entry for entry in declared if isinstance(entry, dict) and entry.get("path") == info_relative]
    if (
        len(info_records) != 1
        or info_records[0].get("mode") != "data"
        or type(info_records[0].get("size")) is not int
        or not 0 <= info_records[0]["size"] <= MAX_INFO_PLIST_BYTES
    ):
        raise PluginFormatError("bundle payload requires one bounded signed Info.plist")

    info_path = root / info_relative
    try:
        info_data = info_path.read_bytes()
        if len(info_data) > MAX_INFO_PLIST_BYTES:
            raise PluginFormatError("bundle Info.plist exceeds 64 KiB")
        info = plistlib.loads(info_data)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise PluginFormatError(f"invalid bundle Info.plist: {exc}") from exc
    if not isinstance(info, dict):
        raise PluginFormatError("bundle Info.plist must be a property-list dictionary")

    expected = {
        "CFBundleExecutable": executable_name,
        "CFBundleIdentifier": manifest["pluginIdentifier"],
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": manifest["displayVersion"],
        "CFBundleVersion": manifest["buildVersion"],
    }
    for key, value in expected.items():
        if not isinstance(info.get(key), str) or info[key] != value:
            raise PluginFormatError(f"bundle Info.plist mismatch for {key}")


def verify_inventory(root: Path, manifest: dict[str, Any]) -> None:
    payload = manifest.get("payload")
    if not isinstance(payload, dict) or not isinstance(payload.get("executablePath"), str):
        raise PluginFormatError("manifest payload is malformed")
    actual = inventory(root, payload["executablePath"])
    declared = manifest.get("files")
    if declared != actual:
        raise PluginFormatError("signed file inventory differs from package bytes")
    code_identity = payload.get("codeIdentity")
    if code_identity is not None:
        if code_identity != macho_code_identity(root / payload["executablePath"]):
            raise PluginFormatError("signed Mach-O code identity differs from package bytes")


def verify_exact_package_files(root: Path, manifest: dict[str, Any]) -> None:
    declared_paths = {entry["path"] for entry in manifest["files"]}
    declared_paths.add("Manifest.json")
    declared_paths.update(path for _, path in signature_paths(manifest))
    actual_paths = {relative for relative, _, _ in _walk_regular_files(root)}
    if actual_paths != declared_paths:
        raise PluginFormatError("package contains missing or unlisted regular files")


def signature_paths(manifest: dict[str, Any]) -> Iterable[tuple[str, str]]:
    publisher = manifest.get("publisher")
    if not isinstance(publisher, dict):
        raise PluginFormatError("publisher block is missing")
    identifiers = publisher.get("signatureKeyIdentifiers")
    if not isinstance(identifiers, list) or not identifiers or len(identifiers) > 8:
        raise PluginFormatError("signatureKeyIdentifiers must contain one to eight keys")
    for identifier in identifiers:
        if not isinstance(identifier, str) or len(identifier) != 64 or any(
            character not in "0123456789abcdef" for character in identifier
        ):
            raise PluginFormatError("invalid publisher key identifier")
        yield identifier, f"Signatures/{identifier}.sig"
