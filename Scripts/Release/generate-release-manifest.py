#!/usr/bin/env python3
"""Generate and validate the exact Battman release asset manifest."""

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
    require_new_output,
    require_package_version,
    require_version,
    sha256_file,
    source_date_epoch,
    write_json,
)
from plugin_release_pins import validate_signed_plugin_release_pins


FINAL_METADATA_NAMES = frozenset({
    "release-manifest.json",
    "SHA256SUMS",
    "SHA256SUMS.p256.sig",
    "SHA256SUMS.p256.pub",
})

HAVOC_ELIGIBLE_ARTIFACT_KINDS = (
    "host-debian-rooted",
    "host-debian-rootless",
    "plugin-debian-rooted",
    "plugin-debian-rootless",
)
HAVOC_MANUAL_CANDIDATE_CHANNEL = "havoc-manual-candidate"


def _unique_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json(path: Path, label: str) -> dict[str, Any]:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink() or lexical.stat().st_size > 512 * 1024:
        raise ReleaseError(f"{label} must be one bounded regular JSON file")
    try:
        value = json.loads(
            lexical.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object_pairs,
        )
    except ReleaseError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise ReleaseError(f"{label} must contain one JSON object")
    return value


def _selected_official_identifiers(matrix: dict[str, Any]) -> list[str]:
    selection = matrix.get("officialPluginSelection")
    identifiers = selection.get("separatelyShipped") if isinstance(selection, dict) else None
    if not isinstance(identifiers, list) or not identifiers:
        raise ReleaseError("release matrix has no selected official plug-ins")
    validated = [
        require_identifier(value, "selected official plug-in identifier")
        for value in identifiers if isinstance(value, str)
    ]
    if len(validated) != len(identifiers) or len(set(validated)) != len(validated):
        raise ReleaseError("release matrix official plug-in selection is malformed")
    return sorted(validated, key=lambda value: value.encode("utf-8"))


def _sdk_example_identifier(matrix: dict[str, Any]) -> str:
    example = matrix.get("sdkExample")
    if not isinstance(example, dict) or set(example) != {
        "pluginIdentifier", "signedPackageRequired", "publisherIdentityReviewRequired",
        "officialTrustDelegation", "rootedRootlessAddOns", "replacementTIPAInclusion",
        "activationPolicy",
    } or example.get("signedPackageRequired") is not True or \
            example.get("publisherIdentityReviewRequired") is not True or \
            example.get("officialTrustDelegation") is not False or \
            example.get("rootedRootlessAddOns") is not False or \
            example.get("replacementTIPAInclusion") is not False or \
            example.get("activationPolicy") != "third-party-explicit-approval-required":
        raise ReleaseError("release matrix SDK example policy is malformed")
    identifier = example.get("pluginIdentifier")
    if not isinstance(identifier, str):
        raise ReleaseError("release matrix SDK example identifier is malformed")
    return require_identifier(identifier, "SDK example identifier")


def _havoc_manual_submission_policy(matrix: dict[str, Any]) -> dict[str, Any]:
    policy = matrix.get("havocManualSubmission")
    expected = {
        "submissionMode": "manual-owner-upload-only",
        "automaticUpload": False,
        "eligibleArtifactKinds": list(HAVOC_ELIGIBLE_ARTIFACT_KINDS),
        "eligibleFilenameSuffix": ".deb",
        "ownerApprovalRequired": True,
        "classificationReviewRequired": True,
        "dualHostingReviewRequired": True,
        "publicationStateAuthority": "owner-maintained-external-record",
    }
    if policy != expected:
        raise ReleaseError("release matrix Havoc manual-submission policy is malformed")
    return policy


def _artifact_channels(
    policy: dict[str, Any],
    name: str,
    kind: str,
    base_channels: list[str],
) -> list[str]:
    eligible = kind in policy["eligibleArtifactKinds"]
    if eligible and not name.endswith(policy["eligibleFilenameSuffix"]):
        raise ReleaseError("Havoc manual candidate is not a Debian package")
    channels = list(base_channels)
    if eligible:
        channels.append(HAVOC_MANUAL_CANDIDATE_CHANNEL)
    return channels


def _package_version(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise ReleaseError(f"{label} is missing or malformed")
    return require_package_version(value, label)


def _matrix_asset_names(
    matrix: dict[str, Any],
    version: str,
    official_versions: dict[str, str],
    sdk_example_identifier: str,
    sdk_example_version: str,
) -> set[str]:
    templates = matrix.get("githubAssets")
    if not isinstance(templates, list) or not templates or any(
        not isinstance(value, str) or not value or len(value) > 512
        for value in templates
    ) or len(templates) != len(set(templates)):
        raise ReleaseError("release matrix GitHub asset templates are malformed")

    result: set[str] = set()

    def add(rendered: str) -> None:
        if (
            not rendered
            or rendered in result
            or Path(rendered).name != rendered
            or rendered in (".", "..")
            or re.search(r"[@<>]", rendered)
        ):
            raise ReleaseError(f"release matrix emitted an unsafe or duplicate asset: {rendered}")
        result.add(rendered)

    for raw in templates:
        rendered = raw.replace("@VERSION@", version)
        has_official = "<plugin-identifier>" in rendered or "<plugin-version>" in rendered
        has_example = (
            "<sdk-example-identifier>" in rendered
            or "<sdk-example-version>" in rendered
        )
        if has_official and has_example:
            raise ReleaseError("release matrix asset template mixes official and SDK identities")
        if has_official:
            if "<plugin-identifier>" not in rendered or "<plugin-version>" not in rendered:
                raise ReleaseError("release matrix official plug-in template is incomplete")
            for identifier, plugin_version in official_versions.items():
                add(rendered.replace("<plugin-identifier>", identifier).replace(
                    "<plugin-version>", plugin_version
                ))
        elif has_example:
            if (
                "<sdk-example-identifier>" not in rendered
                or "<sdk-example-version>" not in rendered
            ):
                raise ReleaseError("release matrix SDK example template is incomplete")
            add(rendered.replace(
                "<sdk-example-identifier>", sdk_example_identifier
            ).replace("<sdk-example-version>", sdk_example_version))
        else:
            add(rendered)
    return result


def _artifact_record(
    path: Path,
    kind: str,
    channels: list[str],
    activation_policy: str,
    *,
    package: str | None = None,
) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ReleaseError(f"release manifest asset must be one regular file: {path}")
    record: dict[str, Any] = {
        "activationPolicy": activation_policy,
        "channels": channels,
        "kind": kind,
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
    }
    if package is not None:
        record["package"] = package
    return record


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-directory", required=True, type=Path)
    parser.add_argument("--release-matrix", required=True, type=Path)
    parser.add_argument("--inspection", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--engineering-candidate", action="store_true")
    parser.add_argument("--unsigned-candidate", action="store_true")
    arguments = parser.parse_args()

    epoch = source_date_epoch(arguments.source_date_epoch)
    if arguments.engineering_candidate and arguments.unsigned_candidate:
        raise ReleaseError("engineering and unsigned strict candidate modes are exclusive")
    version = require_version(arguments.version)
    commit = require_git_commit(arguments.commit)
    release = arguments.release_directory.expanduser().resolve()
    if not release.is_dir() or release.is_symlink():
        raise ReleaseError("release manifest input must be one real release directory")
    output = require_new_output(arguments.output, ".json")
    if output.parent != release or output.name != "release-manifest.json":
        raise ReleaseError("release manifest output must be release-manifest.json in the release directory")

    matrix = _load_json(arguments.release_matrix, "release matrix")
    havoc_policy = _havoc_manual_submission_policy(matrix)
    repository = Path(__file__).resolve().parents[2]
    official_release_pins, sdk_example_release_pin = validate_signed_plugin_release_pins(
        repository, matrix
    )
    inspection = _load_json(arguments.inspection, "artifact inspection")
    if inspection.get("status") != "passed" or inspection.get("version") != version:
        raise ReleaseError("artifact inspection is not a passed report for this release")
    if inspection.get("sourceDateEpoch") != epoch:
        raise ReleaseError("artifact inspection source epoch differs from this release")
    inspected = inspection.get("artifacts")
    if not isinstance(inspected, list):
        raise ReleaseError("artifact inspection has no artifact list")
    inspected_by_name: dict[str, dict[str, Any]] = {}
    for item in inspected:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str):
            raise ReleaseError("artifact inspection contains a malformed record")
        name = item["name"]
        if name in inspected_by_name:
            raise ReleaseError(f"artifact inspection contains duplicate asset {name}")
        inspected_by_name[name] = item

    official_ids = _selected_official_identifiers(matrix)
    sdk_example_id = _sdk_example_identifier(matrix)
    artifacts: list[dict[str, Any]] = []
    used_inspection_names: set[str] = set()

    def inspected_record(name: str, expected_kind: str) -> dict[str, Any]:
        item = inspected_by_name.get(name)
        path = release / name
        if (
            not item
            or item.get("kind") != expected_kind
            or not path.is_file()
            or path.is_symlink()
            or item.get("size") != path.stat().st_size
            or item.get("sha256") != sha256_file(path)
        ):
            raise ReleaseError(f"release manifest inspection mismatch: {name}")
        used_inspection_names.add(name)
        return item

    host_assets = (
        (f"com.torrekie.battman_{version}_iphoneos-arm.deb", "host-debian-rooted", ["github", "apt-rooted"]),
        (f"com.torrekie.battman_{version}_iphoneos-arm64.deb", "host-debian-rootless", ["github", "apt-rootless"]),
        ("Battman.tipa", "trollstore-replacement-tipa", ["github", "trollstore-replacement"]),
    )
    for name, kind, channels in host_assets:
        inspected_record(name, kind)
        artifacts.append(_artifact_record(
            release / name, kind,
            _artifact_channels(havoc_policy, name, kind, channels), "host-artifact",
            package="com.torrekie.battman",
        ))

    report_name = "Battman.tipa.report.json"
    report = _load_json(release / report_name, "TIPA report")
    if (
        report.get("artifact") != "Battman.tipa"
        or report.get("artifactSHA256") != sha256_file(release / "Battman.tipa")
        or report.get("version") != version
        or report.get("requiresOuterResign") is not True
    ):
        raise ReleaseError("TIPA report identity differs from the release")
    embedded_plugins = report.get("embeddedPlugins")
    if not isinstance(embedded_plugins, list) or any(
        not isinstance(item, dict) or not isinstance(item.get("pluginIdentifier"), str)
        for item in embedded_plugins
    ):
        raise ReleaseError("TIPA report contains a malformed embedded plug-in list")
    sealed_ids = sorted(
        (require_identifier(item["pluginIdentifier"], "TIPA embedded plug-in identifier")
         for item in embedded_plugins),
        key=lambda value: value.encode("utf-8"),
    )
    if len(sealed_ids) != len(set(sealed_ids)):
        raise ReleaseError("TIPA report contains duplicate embedded plug-ins")
    if sealed_ids != official_ids:
        raise ReleaseError("replacement TIPA plug-in set differs from official selection")
    artifacts.append(_artifact_record(
        release / report_name, "trollstore-replacement-report",
        ["github", "trollstore-replacement"], "review-report",
    ))

    official_transport_records: dict[str, dict[str, Any]] = {}
    for item in inspected:
        if not isinstance(item, dict) or item.get("kind") != "plugin-transport":
            continue
        identifier = item.get("package")
        if not isinstance(identifier, str) or identifier in official_transport_records:
            raise ReleaseError("artifact inspection has malformed official transports")
        official_transport_records[identifier] = item
    official_versions: dict[str, str] = {}
    for identifier in official_ids:
        transport = official_transport_records.get(identifier)
        if not isinstance(transport, dict):
            raise ReleaseError(f"official plug-in transport is missing: {identifier}")
        plugin_version = _package_version(
            transport.get("version"), "official plug-in version"
        )
        expected_identity = official_release_pins[identifier].manifest_record()
        inspected_identity = {
            "buildVersion": transport.get("buildVersion"),
            "displayVersion": transport.get("displayVersion"),
            "pluginIdentifier": transport.get("package"),
            "releaseSequence": transport.get("releaseSequence"),
        }
        if inspected_identity != expected_identity or plugin_version != expected_identity[
            "displayVersion"
        ]:
            raise ReleaseError(
                f"official plug-in signed release identity differs from its pin: {identifier}"
            )
        official_versions[identifier] = plugin_version
        names = (
            (f"{identifier}_{plugin_version}.battman.zip", "plugin-transport", ["github", "direct-import"]),
            (f"{identifier}_{plugin_version}_iphoneos-arm.deb", "plugin-debian-rooted", ["github", "apt-rooted"]),
            (f"{identifier}_{plugin_version}_iphoneos-arm64.deb", "plugin-debian-rootless", ["github", "apt-rootless"]),
        )
        for name, kind, channels in names:
            item = inspected_record(name, kind)
            if item.get("package") != identifier:
                raise ReleaseError(f"official plug-in artifact identity mismatch: {name}")
            artifacts.append(_artifact_record(
                release / name, kind,
                _artifact_channels(havoc_policy, name, kind, channels),
                "official-delegation-required",
                package=identifier,
            ))

    example_records = [
        item for item in inspected
        if isinstance(item, dict) and item.get("kind") == "sdk-example-transport"
    ]
    if len(example_records) != 1 or example_records[0].get("package") != sdk_example_id:
        raise ReleaseError("SDK example inspection does not match the release matrix")
    example_version = _package_version(
        example_records[0].get("version"), "SDK example version"
    )
    example_identity = {
        "buildVersion": example_records[0].get("buildVersion"),
        "displayVersion": example_records[0].get("displayVersion"),
        "pluginIdentifier": example_records[0].get("package"),
        "releaseSequence": example_records[0].get("releaseSequence"),
    }
    if example_identity != sdk_example_release_pin.manifest_record() or \
            example_version != sdk_example_release_pin.display_version:
        raise ReleaseError("SDK example signed release identity differs from its pin")
    example_name = f"{sdk_example_id}_{example_version}.battman.zip"
    inspected_record(example_name, "sdk-example-transport")
    artifacts.append(_artifact_record(
        release / example_name, "sdk-example-transport", ["github", "direct-import"],
        "third-party-explicit-approval-required", package=sdk_example_id,
    ))

    fixed_assets = (
        (f"BattmanPluginSDK-{version}.tar.gz", "plugin-sdk", ["github"], "source-only"),
        ("compatibility-matrix.json", "compatibility-matrix", ["github"], "review-contract"),
        ("artifact-inspection.json", "artifact-inspection", ["github"], "review-report"),
        ("release-notes.md", "release-notes", ["github"], "review-report"),
        ("release-sbom.cdx.json", "release-sbom", ["github"], "review-report"),
        ("release-provenance.intoto.jsonl", "release-provenance", ["github"], "review-report"),
    )
    for name, kind, channels, policy in fixed_assets:
        path = release / name
        if kind in {"plugin-sdk", "compatibility-matrix"}:
            inspected_record(name, kind)
        artifacts.append(_artifact_record(path, kind, channels, policy))

    if used_inspection_names != set(inspected_by_name):
        raise ReleaseError("artifact inspection contains an unselected or unclassified asset")

    release_entries = list(release.iterdir())
    if any(not path.is_file() or path.is_symlink() for path in release_entries):
        raise ReleaseError("release manifest input contains a non-regular entry")
    actual_names = {path.name for path in release_entries}
    artifact_names = {item["name"] for item in artifacts}
    if actual_names != artifact_names:
        unexpected = sorted(actual_names - artifact_names)
        missing = sorted(artifact_names - actual_names)
        raise ReleaseError(
            f"release manifest pre-sign asset set mismatch; unexpected={unexpected}, missing={missing}"
        )

    expected_final_set = artifact_names | FINAL_METADATA_NAMES
    matrix_names = _matrix_asset_names(
        matrix, version, official_versions, sdk_example_id, example_version
    )
    if matrix_names != expected_final_set:
        unexpected = sorted(matrix_names - expected_final_set)
        missing = sorted(expected_final_set - matrix_names)
        raise ReleaseError(
            f"release matrix asset set mismatch; unexpected={unexpected}, missing={missing}"
        )
    expected_final_names = sorted(
        expected_final_set, key=lambda value: value.encode("utf-8")
    )
    artifacts.sort(key=lambda item: item["name"].encode("utf-8"))
    value = {
        "artifacts": artifacts,
        "commit": commit,
        "expectedFinalAssetNames": expected_final_names,
        "havocManualSubmission": {
            "automaticUpload": False,
            "candidateChannel": HAVOC_MANUAL_CANDIDATE_CHANNEL,
            "classificationReviewRequired": True,
            "dualHostingReviewRequired": True,
            "ownerApprovalRequired": True,
            "publicationState": "not-recorded-by-release-manifest",
        },
        "mode": "engineering-candidate" if arguments.engineering_candidate else "strict-release-candidate",
        "publicationAuthorized": False,
        "schemaVersion": 1,
        "selectedOfficialPluginIdentifiers": official_ids,
        "signedPluginReleasePins": {
            "official": [
                official_release_pins[identifier].manifest_record()
                for identifier in official_ids
            ],
            "sdkExample": sdk_example_release_pin.manifest_record(),
        },
        "sdkExampleIdentifier": sdk_example_id,
        "version": version,
    }
    if arguments.unsigned_candidate:
        value["checksumSignatureProcess"] = "offline-detached"
    write_json(output, value, epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
