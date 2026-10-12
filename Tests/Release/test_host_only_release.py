#!/usr/bin/env python3
"""Pure-Python coverage of source-only examples and an empty plug-in release.

Host bytes are deliberately synthetic unit fixtures. This checks archive and
manifest boundaries, not native signing, compilation, or installability.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/Release"))
from plugin_release_pins import validate_signed_plugin_release_pins
from release_common import ReleaseError, sha256_file
from release_inspection import inspect_sdk, inspect_tipa

EPOCH = 1700000000
VERSION = "1.1.0"
COMMIT = "a" * 40


def run(script, *arguments, success=True):
    result = subprocess.run([sys.executable, str(ROOT / "Scripts/Release" / script),
                             *map(str, arguments)], text=True, capture_output=True)
    assert (result.returncode == 0) == success, result.stderr or result.stdout
    return result


def record(path, kind):
    return {"name": path.name, "kind": kind, "size": path.stat().st_size,
            "sha256": sha256_file(path)}


def main():
    matrix_path = ROOT / "Packaging/Release/release-matrix.json"
    matrix = json.loads(matrix_path.read_text())
    assert validate_signed_plugin_release_pins(ROOT, matrix) == ({}, None)
    assert matrix["officialPluginSelection"]["separatelyShipped"] == []
    assert matrix["officialPluginSelection"]["replacementTIPAIncludesSeparatelyShipped"] is False
    assert not any("<plugin-" in name or "<sdk-example-" in name for name in matrix["githubAssets"])
    assembly_spec = importlib.util.spec_from_file_location("host_only_assembly", ROOT / "Scripts/Release/assemble-release.py")
    assembly = importlib.util.module_from_spec(assembly_spec)
    assembly_spec.loader.exec_module(assembly)
    assert assembly._selected_official_plugin_identifiers(ROOT) == []
    assert assembly._sdk_example_identifier(ROOT) is None

    with tempfile.TemporaryDirectory(prefix="battman-host-only-release-") as raw:
        temporary = Path(raw)
        stage = temporary / "source"
        for relative in ("PluginSDK", "OfficialPlugins/ChargeGauge", "LICENSE"):
            shutil.copytree(ROOT / relative, stage / relative,
                            ignore=shutil.ignore_patterns("build", "__pycache__", "*.pyc", "Packages", ".DS_Store"))
        release = temporary / "release"
        release.mkdir()
        sdk = release / f"BattmanPluginSDK-{VERSION}.tar.gz"
        examples = release / f"BattmanPluginExamples-{VERSION}.tar.gz"
        run("build-sdk-archive.py", "--sdk", stage / "PluginSDK", "--version", VERSION,
            "--output", sdk, "--source-date-epoch", EPOCH)
        run("build-example-source-archive.py", "--repo", stage, "--version", VERSION,
            "--output", examples, "--source-date-epoch", EPOCH)
        inspected = [inspect_sdk(sdk, VERSION, False), inspect_sdk(examples, VERSION, False, examples=True)]
        for architecture, flavor in (("iphoneos-arm", "rooted"), ("iphoneos-arm64", "rootless")):
            path = release / f"com.torrekie.battman_{VERSION}_{architecture}.deb"
            path.write_bytes(b"synthetic host manifest fixture\n")
            inspected.append(record(path, f"host-debian-{flavor}"))
        tipa = release / "Battman.tipa"
        with zipfile.ZipFile(tipa, "w") as archive:
            archive.writestr("Payload/Battman.app/fixture.txt", "host-only unit fixture")
        inspected.append({**record(tipa, "trollstore-replacement-tipa"), "sealedPluginIdentifiers": []})
        report = {"artifact": tipa.name, "artifactSHA256": sha256_file(tipa),
                  "version": VERSION, "requiresOuterResign": True, "embeddedPlugins": []}
        (release / "Battman.tipa.report.json").write_text(json.dumps(report))
        compatibility = release / "compatibility-matrix.json"
        shutil.copy2(ROOT / "Packaging/Release/compatibility-matrix.json", compatibility)
        inspected.append(record(compatibility, "compatibility-matrix"))
        inspection = release / "artifact-inspection.json"
        inspection.write_text(json.dumps({"status": "passed", "version": VERSION,
                                          "sourceDateEpoch": EPOCH, "artifacts": inspected}))
        for name in ("release-notes.md", "release-sbom.cdx.json", "release-provenance.intoto.jsonl"):
            (release / name).write_text("unit fixture\n")
        manifest = release / "release-manifest.json"
        run("generate-release-manifest.py", "--release-directory", release,
            "--release-matrix", matrix_path, "--inspection", inspection,
            "--version", VERSION, "--commit", COMMIT, "--output", manifest,
            "--source-date-epoch", EPOCH, "--unsigned-candidate")
        value = json.loads(manifest.read_text())
        assert value["selectedOfficialPluginIdentifiers"] == []
        assert value["sdkExampleIdentifier"] is None
        assert value["signedPluginReleasePins"] == {"official": [], "sdkExample": None}
        assert not any(item["kind"] in {"plugin-transport", "sdk-example-transport", "plugin-debian-rooted", "plugin-debian-rootless"}
                       for item in value["artifacts"])
        (release / "SHA256SUMS.p256.pub").write_text("synthetic checksum public input; never used for signing\n")
        assets = sorted(release.iterdir())
        run("generate-checksums.py", *[arg for path in assets for arg in ("--asset", path)],
            "--output", release / "SHA256SUMS", "--source-date-epoch", EPOCH)
        run("verify-release-directory.py", release, "--allow-missing-offline-signature")

        # Reject binary plug-ins even if their manifest labels have been hidden.
        with zipfile.ZipFile(tipa, "a") as archive:
            archive.writestr("Payload/Battman.app/PlugIns/Unexpected.bundle/code", "fixture")
        try:
            inspect_tipa(tipa, VERSION, require_host_only=True)
        except ReleaseError as error:
            assert "host-only TIPA" in str(error), error
        else:
            raise AssertionError("host-only TIPA accepted a plug-in root")
        mutated = next(item for item in value["artifacts"] if item["name"] == tipa.name)
        mutated["sha256"] = sha256_file(tipa)
        mutated["size"] = tipa.stat().st_size
        manifest.write_text(json.dumps(value))
        result = run("verify-release-directory.py", release, "--allow-missing-offline-signature", success=False)
        assert "host-only TIPA" in result.stderr

        # Source-only inspection rejects a native payload disguised as source.
        (stage / "OfficialPlugins/ChargeGauge/disguised.c").write_bytes(b"\x7fELFfixture")
        contaminated = temporary / "contaminated.tar.gz"
        run("build-example-source-archive.py", "--repo", stage, "--version", VERSION,
            "--output", contaminated, "--source-date-epoch", EPOCH)
        try:
            inspect_sdk(contaminated, VERSION, False, examples=True)
        except ReleaseError as error:
            assert "native executable" in str(error), error
        else:
            raise AssertionError("example source archive accepted native bytes")
    print("Host-only release, SDK/example source archives, null pins, and binary rejection passed (no native build).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
