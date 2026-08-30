#!/usr/bin/env python3
"""Validate owner-reviewed identities for signed plug-in release inputs."""

from __future__ import annotations

import json
import plistlib
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any
from xml.parsers.expat import ExpatError

from release_common import (
    ReleaseError,
    require_identifier,
    require_package_version,
)


MAX_JSON_INTEGER = 9_007_199_254_740_991
MAX_SOURCE_METADATA_BYTES = 512 * 1024


@dataclass(frozen=True)
class SignedPluginReleasePin:
    plugin_identifier: str
    release_role: str
    display_version: str
    build_version: str
    release_sequence: int

    def manifest_record(self) -> dict[str, object]:
        return {
            "buildVersion": self.build_version,
            "displayVersion": self.display_version,
            "pluginIdentifier": self.plugin_identifier,
            "releaseSequence": self.release_sequence,
        }


def _unique_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ReleaseError(f"duplicate JSON key in signed plug-in release metadata: {key}")
        value[key] = item
    return value


def _regular_repo_file(repo: Path, value: object, label: str) -> Path:
    if not isinstance(value, str) or not value or len(value) > 512 or "\\" in value:
        raise ReleaseError(f"{label} must be one bounded repository-relative path")
    raw_parts = value.split("/")
    if any(part in ("", ".", "..") for part in raw_parts):
        raise ReleaseError(f"{label} must be one canonical repository-relative path")
    relative = PurePosixPath(value)
    if relative.is_absolute() or relative in (PurePosixPath("."), PurePosixPath("..")) or \
            any(part in ("", ".", "..") for part in relative.parts):
        raise ReleaseError(f"{label} must be one bounded repository-relative path")
    try:
        repo = repo.expanduser().resolve(strict=True)
    except OSError as error:
        raise ReleaseError("repository root is missing or inaccessible") from error
    if not repo.is_dir():
        raise ReleaseError("repository root must be one real directory")
    path = repo.joinpath(*relative.parts)

    current = repo
    entry = None
    for index, part in enumerate(relative.parts):
        current /= part
        try:
            component = current.lstat()
        except OSError as error:
            raise ReleaseError(f"{label} is missing: {value}") from error
        if stat.S_ISLNK(component.st_mode):
            raise ReleaseError(f"{label} must not traverse a symbolic link: {value}")
        if index + 1 < len(relative.parts) and not stat.S_ISDIR(component.st_mode):
            raise ReleaseError(f"{label} has a non-directory path component: {value}")
        entry = component
    try:
        resolved = path.resolve(strict=True)
        resolved.relative_to(repo)
    except (OSError, ValueError) as error:
        raise ReleaseError(f"{label} must resolve within the repository: {value}") from error
    if entry is None:
        raise ReleaseError(f"{label} must be one bounded repository-relative path")
    if (
        value != relative.as_posix()
        or not stat.S_ISREG(entry.st_mode)
        or stat.S_ISLNK(entry.st_mode)
        or entry.st_nlink != 1
        or entry.st_size <= 0
        or entry.st_size > MAX_SOURCE_METADATA_BYTES
    ):
        raise ReleaseError(f"{label} must be one bounded real regular file: {value}")
    return path


def _strict_json_file(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object_pairs,
        )
    except ReleaseError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise ReleaseError(f"{label} must contain one JSON object")
    return value


def _release_sequence(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or \
            not 1 <= value <= MAX_JSON_INTEGER:
        raise ReleaseError(f"{label} must be an integer from 1 through {MAX_JSON_INTEGER}")
    return value


def _pin_record(value: object, expected_role: str, label: str) -> tuple[SignedPluginReleasePin, dict[str, str]]:
    expected_keys = {
        "pluginIdentifier", "releaseRole", "displayVersion", "buildVersion",
        "releaseSequence", "sourceBindings",
    }
    if not isinstance(value, dict) or set(value) != expected_keys:
        raise ReleaseError(f"{label} has missing, malformed, or unknown keys")
    role = value.get("releaseRole")
    if role != expected_role:
        raise ReleaseError(f"{label} has the wrong release role")
    identifier = value.get("pluginIdentifier")
    display_version = value.get("displayVersion")
    build_version = value.get("buildVersion")
    if not isinstance(identifier, str) or not isinstance(display_version, str) or \
            not isinstance(build_version, str):
        raise ReleaseError(f"{label} release identity is malformed")
    pin = SignedPluginReleasePin(
        plugin_identifier=require_identifier(identifier, f"{label} identifier"),
        release_role=role,
        display_version=require_package_version(display_version, f"{label} displayVersion"),
        build_version=require_package_version(build_version, f"{label} buildVersion"),
        release_sequence=_release_sequence(value.get("releaseSequence"), f"{label} releaseSequence"),
    )
    bindings = value.get("sourceBindings")
    required_bindings = {"manifestTemplate", "bundleInfoPlist"}
    optional_bindings = {"displayVersionFile", "buildVersionFile"}
    if not isinstance(bindings, dict) or not required_bindings <= set(bindings) or \
            not set(bindings) <= required_bindings | optional_bindings or \
            any(not isinstance(item, str) for item in bindings.values()):
        raise ReleaseError(f"{label} source bindings are malformed")
    return pin, bindings


def _require_identity(value: dict[str, Any], pin: SignedPluginReleasePin, label: str) -> None:
    expected = pin.manifest_record()
    for key, expected_value in expected.items():
        if value.get(key) != expected_value or type(value.get(key)) is not type(expected_value):
            raise ReleaseError(
                f"{label} {key} differs from the release pin for {pin.plugin_identifier}"
            )


def _validate_source_bindings(
    repo: Path,
    pin: SignedPluginReleasePin,
    bindings: dict[str, str],
    label: str,
) -> None:
    template_path = _regular_repo_file(
        repo, bindings["manifestTemplate"], f"{label} manifest template"
    )
    template = _strict_json_file(template_path, f"{label} manifest template")
    _require_identity(template, pin, f"{label} manifest template")

    info_path = _regular_repo_file(
        repo, bindings["bundleInfoPlist"], f"{label} bundle Info.plist"
    )
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (
        OSError,
        plistlib.InvalidFileException,
        ValueError,
        TypeError,
        AttributeError,
        OverflowError,
        IndexError,
        KeyError,
        ExpatError,
    ) as error:
        raise ReleaseError(f"{label} bundle Info.plist is malformed") from error
    expected_info = {
        "CFBundleIdentifier": pin.plugin_identifier,
        "CFBundleShortVersionString": pin.display_version,
        "CFBundleVersion": pin.build_version,
    }
    if not isinstance(info, dict) or any(info.get(key) != expected for key, expected in expected_info.items()):
        raise ReleaseError(f"{label} bundle Info.plist differs from its release pin")

    for binding_name, expected in (
        ("displayVersionFile", pin.display_version),
        ("buildVersionFile", pin.build_version),
    ):
        raw_path = bindings.get(binding_name)
        if raw_path is None:
            continue
        path = _regular_repo_file(repo, raw_path, f"{label} {binding_name}")
        try:
            data = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise ReleaseError(f"{label} {binding_name} is not valid UTF-8") from error
        if data.rstrip("\r\n") != expected or data[:len(expected)] != expected or \
                data[len(expected):] not in ("", "\n", "\r\n"):
            raise ReleaseError(f"{label} {binding_name} differs from its release pin")


def validate_signed_plugin_release_pins(
    repo: Path,
    matrix: dict[str, Any],
) -> tuple[dict[str, SignedPluginReleasePin], SignedPluginReleasePin]:
    """Validate the matrix pins and bind them to canonical source metadata."""
    repo = repo.expanduser().resolve()
    raw = matrix.get("signedPluginReleasePins")
    if not isinstance(raw, dict) or set(raw) != {"official", "sdkExample"}:
        raise ReleaseError("release matrix signed plug-in release pins are malformed")

    selection = matrix.get("officialPluginSelection")
    selected = selection.get("separatelyShipped") if isinstance(selection, dict) else None
    example_policy = matrix.get("sdkExample")
    example_identifier = (
        example_policy.get("pluginIdentifier") if isinstance(example_policy, dict) else None
    )
    if not isinstance(selected, list) or not selected or any(
        not isinstance(identifier, str) for identifier in selected
    ) or not isinstance(example_identifier, str):
        raise ReleaseError("release matrix plug-in selection is malformed")
    selected_identifiers = [
        require_identifier(identifier, "selected official plug-in identifier")
        for identifier in selected
    ]
    example_identifier = require_identifier(example_identifier, "SDK example identifier")

    official_records = raw.get("official")
    if not isinstance(official_records, list) or not official_records:
        raise ReleaseError("release matrix official signed plug-in pins are malformed")
    official: dict[str, SignedPluginReleasePin] = {}
    for index, record in enumerate(official_records):
        label = f"official signed plug-in pin {index + 1}"
        pin, bindings = _pin_record(record, "official", label)
        if pin.plugin_identifier in official:
            raise ReleaseError("release matrix official signed plug-in pins are duplicated")
        _validate_source_bindings(repo, pin, bindings, label)
        official[pin.plugin_identifier] = pin
    canonical_ids = sorted(official, key=lambda value: value.encode("utf-8"))
    if list(official) != canonical_ids or canonical_ids != sorted(
        selected_identifiers, key=lambda value: value.encode("utf-8")
    ):
        raise ReleaseError("release matrix official signed plug-in pins differ from selection")

    sdk_example, bindings = _pin_record(raw.get("sdkExample"), "sdk-example", "SDK example pin")
    if sdk_example.plugin_identifier != example_identifier or example_identifier in official:
        raise ReleaseError("release matrix SDK example pin differs from policy or official selection")
    _validate_source_bindings(repo, sdk_example, bindings, "SDK example pin")
    return official, sdk_example


def read_plugin_package_release_identity(
    package: Path,
    label: str,
) -> dict[str, object]:
    lexical = package.expanduser().absolute()
    if lexical.suffix != ".battman" or not lexical.is_dir() or lexical.is_symlink():
        raise ReleaseError(f"{label} must be one real .battman directory")
    manifest_path = lexical / "Manifest.json"
    try:
        entry = manifest_path.lstat()
    except OSError as error:
        raise ReleaseError(f"{label} Manifest.json is missing") from error
    if not stat.S_ISREG(entry.st_mode) or stat.S_ISLNK(entry.st_mode) or \
            entry.st_size <= 0 or entry.st_size > MAX_SOURCE_METADATA_BYTES:
        raise ReleaseError(f"{label} Manifest.json must be one bounded regular file")
    manifest = _strict_json_file(manifest_path, f"{label} Manifest.json")
    identifier = manifest.get("pluginIdentifier")
    display_version = manifest.get("displayVersion")
    build_version = manifest.get("buildVersion")
    release_sequence = manifest.get("releaseSequence")
    if not isinstance(identifier, str) or not isinstance(display_version, str) or \
            not isinstance(build_version, str):
        raise ReleaseError(f"{label} signed release identity is malformed")
    return {
        "buildVersion": require_package_version(build_version, f"{label} buildVersion"),
        "displayVersion": require_package_version(display_version, f"{label} displayVersion"),
        "pluginIdentifier": require_identifier(identifier, f"{label} identifier"),
        "releaseSequence": _release_sequence(release_sequence, f"{label} releaseSequence"),
    }


def require_plugin_package_matches_pin(
    package: Path,
    pin: SignedPluginReleasePin,
    label: str,
) -> dict[str, object]:
    identity = read_plugin_package_release_identity(package, label)
    expected = pin.manifest_record()
    for key, expected_value in expected.items():
        if identity.get(key) != expected_value or type(identity.get(key)) is not type(expected_value):
            raise ReleaseError(
                f"{label} {key} differs from the release pin for {pin.plugin_identifier}"
            )
    return identity
