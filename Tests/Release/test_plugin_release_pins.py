#!/usr/bin/env python3
"""Focused source-binding tests for signed plug-in release pins."""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts" / "Release"))

from plugin_release_pins import validate_signed_plugin_release_pins  # noqa: E402
from release_common import ReleaseError  # noqa: E402


def source_binding_paths(matrix: dict[str, object]) -> list[Path]:
    pins = matrix["signedPluginReleasePins"]
    records = [*pins["official"], pins["sdkExample"]]
    return sorted({
        Path(relative)
        for record in records
        for relative in record["sourceBindings"].values()
    })


def copy_binding_fixture(destination: Path, matrix: dict[str, object]) -> None:
    for relative in source_binding_paths(matrix):
        target = destination / relative
        target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)


def expect_rejection(repository: Path, matrix: dict[str, object], expected: str) -> None:
    try:
        validate_signed_plugin_release_pins(repository, matrix)
    except ReleaseError as error:
        if expected not in str(error):
            raise AssertionError(f"unexpected release-pin rejection: {error}") from error
    else:
        raise AssertionError(f"release-pin source drift was accepted: {expected}")


def main() -> int:
    matrix = json.loads(
        (ROOT / "Packaging" / "Release" / "release-matrix.json").read_text(
            encoding="utf-8"
        )
    )
    _, example = validate_signed_plugin_release_pins(ROOT, matrix)
    build_version_path = ROOT / "PluginSDK/Examples/AnalyticsCard/BUILD_VERSION"
    assert build_version_path.read_text(encoding="ascii") == example.build_version + "\n"
    source = (
        ROOT / "PluginSDK/Examples/AnalyticsCard/BTAnalyticsExamplePlugin.m"
    ).read_text(encoding="utf-8")
    assert ".pluginVersion = BT_ANALYTICS_EXAMPLE_PLUGIN_VERSION," in source
    assert '.pluginVersion = "1",' not in source

    with tempfile.TemporaryDirectory(prefix="battman-release-pins-") as raw:
        temporary = Path(raw)

        build_drift = temporary / "build-drift"
        copy_binding_fixture(build_drift, matrix)
        (build_drift / build_version_path.relative_to(ROOT)).write_text(
            "2\n", encoding="ascii"
        )
        expect_rejection(build_drift, matrix, "buildVersionFile differs from its release pin")

        plist_drift = temporary / "plist-drift"
        copy_binding_fixture(plist_drift, matrix)
        info_path = plist_drift / "PluginSDK/Examples/AnalyticsCard/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleVersion"] = "2"
        info_path.write_bytes(plistlib.dumps(info, sort_keys=True))
        expect_rejection(plist_drift, matrix, "bundle Info.plist differs from its release pin")

        malformed_plist = temporary / "malformed-plist"
        copy_binding_fixture(malformed_plist, matrix)
        (malformed_plist / "PluginSDK/Examples/AnalyticsCard/Info.plist").write_bytes(
            b'<?xml version="1.0"?><plist version="1.0"><dict>'
            b"<key>schemaVersion</key><date>foo</date>"
            b"</dict></plist>"
        )
        expect_rejection(
            malformed_plist, matrix, "bundle Info.plist is malformed"
        )

        manifest_drift = temporary / "manifest-drift"
        copy_binding_fixture(manifest_drift, matrix)
        manifest_path = (
            manifest_drift / "PluginSDK/Examples/AnalyticsCard/ManifestTemplate.json.in"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["buildVersion"] = "2"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        expect_rejection(
            manifest_drift, matrix, "manifest template buildVersion differs from the release pin"
        )

        linked_repo = temporary / "linked-repo"
        copy_binding_fixture(linked_repo, matrix)
        analytics_card = linked_repo / "PluginSDK/Examples/AnalyticsCard"
        escaped_analytics_card = temporary / "outside-repository/AnalyticsCard"
        escaped_analytics_card.parent.mkdir(mode=0o755, parents=True)
        analytics_card.rename(escaped_analytics_card)
        analytics_card.symlink_to(escaped_analytics_card, target_is_directory=True)
        expect_rejection(linked_repo, matrix, "must not traverse a symbolic link")

        hardlink_repo = temporary / "hardlink-repo"
        copy_binding_fixture(hardlink_repo, matrix)
        hardlink_target = hardlink_repo / "PluginSDK/Examples/AnalyticsCard/Info.plist"
        outside_file = temporary / "outside-info.plist"
        outside_file.write_bytes(hardlink_target.read_bytes())
        hardlink_target.unlink()
        os.link(outside_file, hardlink_target)
        expect_rejection(hardlink_repo, matrix, "bounded real regular file")

        noncanonical_repo = temporary / "noncanonical-repo"
        copy_binding_fixture(noncanonical_repo, matrix)
        noncanonical_matrix = json.loads(json.dumps(matrix))
        noncanonical_matrix["signedPluginReleasePins"]["sdkExample"][
            "sourceBindings"
        ]["bundleInfoPlist"] = "PluginSDK/Examples/AnalyticsCard/./Info.plist"
        expect_rejection(
            noncanonical_repo,
            noncanonical_matrix,
            "canonical repository-relative path",
        )

    print("Signed plug-in release-pin source binding tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
