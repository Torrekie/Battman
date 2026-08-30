#!/usr/bin/env python3
"""Focused contract tests for manual, Deb-only Havoc candidate validation."""

from __future__ import annotations

import contextlib
import io
import importlib.util
import json
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/Release/validate-havoc-candidate.py"
sys.path.insert(0, str(SCRIPT.parent))

spec = importlib.util.spec_from_file_location("validate_havoc_candidate", SCRIPT)
assert spec is not None and spec.loader is not None
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def invoke(arguments: list[str]) -> int:
    previous = sys.argv
    sys.argv = [str(SCRIPT), *arguments]
    try:
        return validator.main()
    finally:
        sys.argv = previous


def main() -> int:
    commit = "a" * 40
    source_tree = "b" * 40
    with tempfile.TemporaryDirectory(prefix="battman-havoc-policy-") as raw:
        temporary = Path(raw)
        comparisons: list[tuple[str, str]] = []
        validator._is_newer = lambda candidate, published: (
            comparisons.append((candidate, published)) or True
        )
        selected_sections: dict[str, str] = {
            "host-rooted.deb": "Applications",
            "host-rootless.deb": "Applications",
            "plugin-rooted.deb": "Tweaks",
            "plugin-rootless.deb": "Tweaks",
        }
        validator._debian_section = lambda path: selected_sections[Path(path).name]

        host_calls: list[tuple[str, str, str]] = []

        def inspect_host(path, flavor, version, package, **identity):
            assert identity == {"commit": commit, "source_tree": source_tree}
            host_calls.append((flavor, version, package))
            return {
                "kind": f"host-debian-{flavor}",
                "name": Path(path).name,
                "package": package,
                "version": version,
            }

        validator.inspect_deb = inspect_host
        host_output = temporary / "host.json"
        assert invoke([
            "--rooted-deb", str(temporary / "host-rooted.deb"),
            "--rootless-deb", str(temporary / "host-rootless.deb"),
            "--version", "1.1.0",
            "--published-version", "1.0.3.3",
            "--commit", commit,
            "--source-tree", source_tree,
            "--output", str(host_output),
            "--source-date-epoch", "1700000000",
        ]) == 0
        host = json.loads(host_output.read_text(encoding="utf-8"))
        assert host_calls == [
            ("rooted", "1.1.0", "com.torrekie.battman"),
            ("rootless", "1.1.0", "com.torrekie.battman"),
        ]
        assert comparisons == [("1.1.0", "1.0.3.3")]
        assert host["status"] == "candidate-only-not-uploaded"
        assert host["candidateEligibility"] == "eligible-for-manual-owner-submission"
        assert host["artifactKind"] == "host-debian-pair"
        assert host["section"] == "Applications"
        assert host["publishedVersionCompared"] == "1.0.3.3"
        assert host["publicationState"] == "not-recorded-by-validator"
        assert host["manualOwnerUploadOnly"] is True
        assert host["automaticUploadPerformed"] is False
        assert host["ownerApprovalRequired"] is True
        assert host["havocClassificationDecisionRequired"] is True
        assert host["dualHostingReviewRequired"] is True

        try:
            invoke([
                "--rooted-deb", str(temporary / "host-rooted.deb"),
                "--rootless-deb", str(temporary / "host-rootless.deb"),
                "--version", "1.1.0",
                "--initial-submission",
                "--commit", commit,
                "--source-tree", source_tree,
                "--output", str(temporary / "host-initial.json"),
                "--source-date-epoch", "1700000000",
            ])
        except validator.ReleaseError as error:
            assert "explicit --published-version" in str(error)
        else:
            raise AssertionError("existing Battman host accepted an initial submission")

        plugin_calls: list[tuple[str, str, str, str]] = []

        def inspect_plugin(path, flavor, version, package, host_version):
            plugin_calls.append((flavor, version, package, host_version))
            return {
                "kind": f"plugin-debian-{flavor}",
                "name": Path(path).name,
                "package": package,
                "version": version,
            }

        validator.inspect_plugin_deb = inspect_plugin
        plugin_output = temporary / "plugin.json"
        assert invoke([
            "--rooted-deb", str(temporary / "plugin-rooted.deb"),
            "--rootless-deb", str(temporary / "plugin-rootless.deb"),
            "--artifact-kind", "plugin",
            "--version", "1.0",
            "--initial-submission",
            "--package", "com.example.battman.plugin",
            "--host-version", "1.1.0",
            "--section", "Tweaks",
            "--commit", commit,
            "--source-tree", source_tree,
            "--output", str(plugin_output),
            "--source-date-epoch", "1700000000",
        ]) == 0
        plugin = json.loads(plugin_output.read_text(encoding="utf-8"))
        assert plugin_calls == [
            ("rooted", "1.0", "com.example.battman.plugin", "1.1.0"),
            ("rootless", "1.0", "com.example.battman.plugin", "1.1.0"),
        ]
        assert comparisons == [("1.1.0", "1.0.3.3")]
        assert plugin["artifactKind"] == "plugin-debian-pair"
        assert plugin["package"] == "com.example.battman.plugin"
        assert plugin["section"] == "Tweaks"
        assert plugin["publishedVersionCompared"] is None
        assert all(item["name"].endswith(".deb") for item in plugin["artifacts"])

        try:
            invoke([
                "--rooted-deb", str(temporary / "invalid-rooted.deb"),
                "--rootless-deb", str(temporary / "invalid-rootless.deb"),
                "--artifact-kind", "plugin",
                "--version", "1.0",
                "--initial-submission",
                "--package", "com.example.battman.plugin",
                "--section", "Applications",
                "--commit", commit,
                "--source-tree", source_tree,
                "--output", str(temporary / "invalid.json"),
                "--source-date-epoch", "1700000000",
            ])
        except validator.ReleaseError as error:
            assert "--host-version" in str(error)
        else:
            raise AssertionError("plug-in Havoc candidate accepted no host version")

        try:
            invoke([
                "--rooted-deb", str(temporary / "plugin-rooted.deb"),
                "--rootless-deb", str(temporary / "plugin-rootless.deb"),
                "--artifact-kind", "plugin",
                "--version", "1.0",
                "--initial-submission",
                "--package", "com.example.battman.plugin",
                "--host-version", "1.1.0",
                "--commit", commit,
                "--source-tree", source_tree,
                "--output", str(temporary / "missing-section.json"),
                "--source-date-epoch", "1700000000",
            ])
        except validator.ReleaseError as error:
            assert "explicit --section" in str(error)
        else:
            raise AssertionError("plug-in Havoc candidate accepted no explicit section")

        selected_sections["plugin-rootless.deb"] = "Applications"
        try:
            invoke([
                "--rooted-deb", str(temporary / "plugin-rooted.deb"),
                "--rootless-deb", str(temporary / "plugin-rootless.deb"),
                "--artifact-kind", "plugin",
                "--version", "1.0",
                "--initial-submission",
                "--package", "com.example.battman.plugin",
                "--host-version", "1.1.0",
                "--section", "Tweaks",
                "--commit", commit,
                "--source-tree", source_tree,
                "--output", str(temporary / "mismatched-section.json"),
                "--source-date-epoch", "1700000000",
            ])
        except validator.ReleaseError as error:
            assert "rootless Havoc Debian Section differs" in str(error)
        else:
            raise AssertionError("Havoc candidate accepted mismatched Debian sections")

        with contextlib.redirect_stderr(io.StringIO()):
            try:
                invoke([
                    "--rooted-deb", str(temporary / "host-rooted.deb"),
                    "--rootless-deb", str(temporary / "host-rootless.deb"),
                    "--version", "1.1.0",
                    "--initial-submission",
                    "--section", "Unknown",
                    "--commit", commit,
                    "--source-tree", source_tree,
                    "--output", str(temporary / "invalid-section.json"),
                ])
            except SystemExit as error:
                assert error.code == 2
            else:
                raise AssertionError("Havoc candidate accepted an unsupported section")

    print("Manual Deb-only Havoc candidate policy passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
