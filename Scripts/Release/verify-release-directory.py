#!/usr/bin/env python3
"""Verify a finalized Battman release directory against its signed manifest set."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from release_common import (
    ReleaseError,
    require_git_commit,
    require_identifier,
    require_package_version,
    require_version,
    sha256_file,
)


CHECKSUM_LINE = re.compile(rb"([0-9a-f]{64})  ([^\r\n/]+)\n")
FINAL_METADATA_NAMES = {
    "release-manifest.json",
    "SHA256SUMS",
    "SHA256SUMS.p256.pub",
    "SHA256SUMS.p256.sig",
}
HEX_SHA256 = re.compile(r"^[0-9a-f]{64}$")
HAVOC_MANUAL_CANDIDATE_CHANNEL = "havoc-manual-candidate"
HAVOC_ELIGIBLE_ARTIFACT_KINDS = frozenset({
    "host-debian-rooted",
    "host-debian-rootless",
    "plugin-debian-rooted",
    "plugin-debian-rootless",
})
HAVOC_MANUAL_SUBMISSION_POLICY = {
    "automaticUpload": False,
    "candidateChannel": HAVOC_MANUAL_CANDIDATE_CHANNEL,
    "classificationReviewRequired": True,
    "dualHostingReviewRequired": True,
    "ownerApprovalRequired": True,
    "publicationState": "not-recorded-by-release-manifest",
}


def _unique_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _bounded_line(value: object, label: str, maximum: int = 512) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > maximum
        or "\n" in value
        or "\r" in value
    ):
        raise ReleaseError(f"{label} must be one bounded non-empty line")
    return value


def _verify_checksums(path: Path, expected_names: set[str]) -> None:
    data = path.read_bytes()
    offset = 0
    seen: set[str] = set()
    while offset < len(data):
        match = CHECKSUM_LINE.match(data, offset)
        if not match:
            raise ReleaseError("release SHA256SUMS contains a malformed line")
        digest = match.group(1).decode("ascii")
        try:
            name = match.group(2).decode("utf-8")
        except UnicodeDecodeError as error:
            raise ReleaseError("release SHA256SUMS contains an invalid UTF-8 name") from error
        if name in seen or name in (".", "..") or "\\" in name:
            raise ReleaseError(f"release SHA256SUMS contains an unsafe name: {name!r}")
        asset = path.parent / name
        if not asset.is_file() or asset.is_symlink() or sha256_file(asset) != digest:
            raise ReleaseError(f"release checksum mismatch: {name}")
        seen.add(name)
        offset = match.end()
    if seen != expected_names:
        raise ReleaseError("release SHA256SUMS does not cover the exact signed asset set")


def _validate_havoc_manual_policy(manifest: dict[str, Any]) -> None:
    policy = manifest.get("havocManualSubmission")
    if (
        not isinstance(policy, dict)
        or set(policy) != set(HAVOC_MANUAL_SUBMISSION_POLICY)
        or any(
            type(policy[key]) is not type(expected) or policy[key] != expected
            for key, expected in HAVOC_MANUAL_SUBMISSION_POLICY.items()
        )
    ):
        raise ReleaseError("release manifest Havoc manual-submission policy is malformed")


def _validate_havoc_artifact_policy(name: str, kind: str, channels: list[str]) -> None:
    for channel in channels:
        if (
            channel.casefold().startswith("havoc")
            and channel != HAVOC_MANUAL_CANDIDATE_CHANNEL
        ):
            raise ReleaseError("release manifest contains a legacy or unknown Havoc channel")
    eligible_kind = kind in HAVOC_ELIGIBLE_ARTIFACT_KINDS
    if eligible_kind and not name.endswith(".deb"):
        raise ReleaseError("Havoc candidate artifact kind must use a Debian filename")
    has_candidate_channel = HAVOC_MANUAL_CANDIDATE_CHANNEL in channels
    if has_candidate_channel != eligible_kind:
        raise ReleaseError(
            "release manifest Havoc candidate channel does not match artifact eligibility"
        )


def _signed_plugin_release_identity(value: object, label: str) -> dict[str, object]:
    expected_keys = {
        "buildVersion", "displayVersion", "pluginIdentifier", "releaseSequence",
    }
    if not isinstance(value, dict) or set(value) != expected_keys:
        raise ReleaseError(f"{label} is malformed")
    identifier = value.get("pluginIdentifier")
    display_version = value.get("displayVersion")
    build_version = value.get("buildVersion")
    release_sequence = value.get("releaseSequence")
    if not isinstance(identifier, str) or not isinstance(display_version, str) or \
            not isinstance(build_version, str) or isinstance(release_sequence, bool) or \
            not isinstance(release_sequence, int) or \
            not 1 <= release_sequence <= 9_007_199_254_740_991:
        raise ReleaseError(f"{label} is malformed")
    return {
        "buildVersion": require_package_version(build_version, f"{label} buildVersion"),
        "displayVersion": require_package_version(
            display_version, f"{label} displayVersion"
        ),
        "pluginIdentifier": require_identifier(identifier, f"{label} identifier"),
        "releaseSequence": release_sequence,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("release_directory", type=Path)
    parser.add_argument("--allow-missing-offline-signature", action="store_true")
    arguments = parser.parse_args()
    release = arguments.release_directory.expanduser().resolve()
    if not release.is_dir() or release.is_symlink():
        raise ReleaseError("release directory must be one real directory")
    manifest_path = release / "release-manifest.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ReleaseError("release-manifest.json is missing or unsafe")
    try:
        if manifest_path.stat().st_size > 2 * 1024 * 1024:
            raise ReleaseError("release-manifest.json exceeds the bounded size")
        manifest = json.loads(
            manifest_path.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object_pairs,
        )
    except ReleaseError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError("release-manifest.json is not valid UTF-8 JSON") from error
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1 or \
            manifest.get("publicationAuthorized") is not False:
        raise ReleaseError("release manifest has an unsupported or unsafe policy")
    _validate_havoc_manual_policy(manifest)
    expected = manifest.get("expectedFinalAssetNames")
    artifacts = manifest.get("artifacts")
    if not isinstance(expected, list) or not expected or len(expected) != len(set(expected)) or \
            any(not isinstance(name, str) or not name or "/" in name or "\\" in name for name in expected):
        raise ReleaseError("release manifest final asset set is malformed")
    if not isinstance(artifacts, list):
        raise ReleaseError("release manifest artifact records are malformed")
    version = manifest.get("version")
    commit = manifest.get("commit")
    if not isinstance(version, str):
        raise ReleaseError("release manifest version is malformed")
    if not isinstance(commit, str):
        raise ReleaseError("release manifest commit is malformed")
    require_version(version, "release manifest version")
    require_git_commit(commit)
    mode = manifest.get("mode")
    if mode not in {
        "engineering-candidate",
        "strict-release-candidate",
    }:
        raise ReleaseError("release manifest mode is malformed")
    signature_process = manifest.get("checksumSignatureProcess")
    if mode == "strict-release-candidate":
        if signature_process != "offline-detached":
            raise ReleaseError("strict release manifest lacks the offline-signature policy")
    elif signature_process is not None:
        raise ReleaseError("engineering release manifest claims a production signature process")
    selected = manifest.get("selectedOfficialPluginIdentifiers")
    if not isinstance(selected, list) or not selected or any(
        not isinstance(value, str) for value in selected
    ):
        raise ReleaseError("release manifest official plug-in selection is malformed")
    validated_selected = [
        require_identifier(value, "release manifest official plug-in identifier")
        for value in selected
    ]
    if validated_selected != sorted(
        set(validated_selected), key=lambda value: value.encode("utf-8")
    ):
        raise ReleaseError("release manifest official plug-in selection is not canonical")
    example_identifier = manifest.get("sdkExampleIdentifier")
    if not isinstance(example_identifier, str):
        raise ReleaseError("release manifest SDK example identifier is malformed")
    require_identifier(example_identifier, "release manifest SDK example identifier")
    if example_identifier in validated_selected:
        raise ReleaseError("release manifest SDK example overlaps official selection")
    signed_pins = manifest.get("signedPluginReleasePins")
    if not isinstance(signed_pins, dict) or set(signed_pins) != {"official", "sdkExample"}:
        raise ReleaseError("release manifest signed plug-in release pins are malformed")
    raw_official_pins = signed_pins.get("official")
    if not isinstance(raw_official_pins, list) or not raw_official_pins:
        raise ReleaseError("release manifest official plug-in release pins are malformed")
    official_pins = [
        _signed_plugin_release_identity(value, "release manifest official plug-in pin")
        for value in raw_official_pins
    ]
    if [value["pluginIdentifier"] for value in official_pins] != validated_selected:
        raise ReleaseError("release manifest official plug-in pins differ from selection")
    sdk_example_pin = _signed_plugin_release_identity(
        signed_pins.get("sdkExample"), "release manifest SDK example pin"
    )
    if sdk_example_pin["pluginIdentifier"] != example_identifier:
        raise ReleaseError("release manifest SDK example pin differs from selection")

    entries = list(release.iterdir())
    if any(not path.is_file() or path.is_symlink() for path in entries):
        raise ReleaseError("release directory contains a non-regular entry")
    actual = sorted((path.name for path in entries), key=lambda value: value.encode("utf-8"))
    if arguments.allow_missing_offline_signature:
        if mode != "strict-release-candidate" or signature_process != "offline-detached":
            raise ReleaseError("missing-signature verification is not authorized by the manifest")
        if "SHA256SUMS.p256.sig" in actual or sorted(
            [*actual, "SHA256SUMS.p256.sig"], key=lambda value: value.encode("utf-8")
        ) != expected:
            raise ReleaseError("unsigned release directory differs from its exact final asset set")
    elif actual != expected:
        raise ReleaseError("release directory differs from the exact final asset set")
    if expected != sorted(expected, key=lambda value: value.encode("utf-8")):
        raise ReleaseError("release manifest final asset set is not canonical")
    seen: set[str] = set()
    for record in artifacts:
        if not isinstance(record, dict) or set(record) not in ({
            "activationPolicy", "channels", "kind", "name", "sha256", "size"
        }, {
            "activationPolicy", "channels", "kind", "name", "package", "sha256", "size"
        }):
            raise ReleaseError("release manifest contains a malformed artifact record")
        name = record.get("name")
        if (
            not isinstance(name, str)
            or Path(name).name != name
            or name in (".", "..")
            or name in seen
            or name not in expected
            or name in FINAL_METADATA_NAMES
        ):
            raise ReleaseError("release manifest contains a duplicate or unknown artifact")
        kind = _bounded_line(record.get("kind"), "release artifact kind", 128)
        _bounded_line(record.get("activationPolicy"), "release artifact activation policy", 128)
        channels = record.get("channels")
        if not isinstance(channels, list) or not channels or any(
            not isinstance(channel, str)
            or _bounded_line(channel, "release artifact channel", 128) != channel
            for channel in channels
        ) or len(channels) != len(set(channels)):
            raise ReleaseError("release manifest contains malformed artifact channels")
        _validate_havoc_artifact_policy(name, kind, channels)
        digest = record.get("sha256")
        size = record.get("size")
        if not isinstance(digest, str) or not HEX_SHA256.fullmatch(digest):
            raise ReleaseError("release manifest contains a malformed artifact digest")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise ReleaseError("release manifest contains a malformed artifact size")
        package = record.get("package")
        if package is not None:
            if not isinstance(package, str):
                raise ReleaseError("release manifest contains a malformed package identity")
            require_identifier(package, "release manifest package identifier")
        seen.add(name)
        path = release / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size != size or \
                sha256_file(path) != digest:
            raise ReleaseError(f"release manifest artifact changed: {name}")
    if set(expected) - seen != FINAL_METADATA_NAMES:
        raise ReleaseError("release manifest coverage exception set is malformed")
    expected_signed_plugin_assets: set[str] = set()
    for pin in official_pins:
        identifier = pin["pluginIdentifier"]
        plugin_version = pin["displayVersion"]
        expected_signed_plugin_assets.update({
            f"{identifier}_{plugin_version}.battman.zip",
            f"{identifier}_{plugin_version}_iphoneos-arm.deb",
            f"{identifier}_{plugin_version}_iphoneos-arm64.deb",
        })
    expected_signed_plugin_assets.add(
        f"{sdk_example_pin['pluginIdentifier']}_{sdk_example_pin['displayVersion']}.battman.zip"
    )
    if not expected_signed_plugin_assets <= seen:
        raise ReleaseError("release manifest signed plug-in assets differ from release pins")
    _verify_checksums(
        release / "SHA256SUMS",
        set(expected) - {"SHA256SUMS", "SHA256SUMS.p256.sig"},
    )
    print(json.dumps({
        "artifactCount": len(actual),
        "mode": mode,
        "recordedArtifactCount": len(artifacts),
        "status": "passed",
        "version": version,
    }, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
