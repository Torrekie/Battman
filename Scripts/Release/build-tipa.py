#!/usr/bin/env python3
"""Build a deterministic replacement TIPA with sealed native plug-ins.

This tool verifies and repackages existing inputs. It never signs, installs,
launches, contacts a device, or invokes TrollStore.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
from pathlib import Path, PurePosixPath

from release_common import (
    ReleaseError,
    copy_tree_normalized,
    deterministic_zip,
    iter_tree,
    load_app_info,
    remove_staged_tree,
    require_input_directory,
    require_new_output,
    require_version,
    run,
    sha256_file,
    source_date_epoch,
    temporary_sibling,
    tree_digest,
    write_json,
)


def _parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--plugin", action="append", default=[], type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--require-release", action="store_true")
    return parser.parse_args()


def _logical_package_digest(metadata: Path, payload: Path, logical_payload: str) -> str:
    """Recreate the transport digest without reconstructing or executing it."""
    records: list[tuple[str, Path, os.stat_result]] = []
    for relative, path, entry in iter_tree(metadata):
        if stat.S_ISREG(entry.st_mode):
            records.append((relative, path, entry))
    for relative, path, entry in iter_tree(payload):
        if stat.S_ISREG(entry.st_mode):
            records.append((f"{logical_payload}/{relative}", path, entry))
    logical_paths = [relative for relative, _, _ in records]
    if len(logical_paths) != len(set(logical_paths)):
        raise ReleaseError("sealed representation produced duplicate logical paths")

    digest = hashlib.sha256()
    for relative, path, entry in sorted(records, key=lambda item: item[0].encode("utf-8")):
        path_bytes = relative.encode("utf-8")
        digest.update(b"F")
        digest.update(len(path_bytes).to_bytes(4, "big"))
        digest.update(path_bytes)
        digest.update(b"\x01" if entry.st_mode & 0o111 else b"\x00")
        digest.update(entry.st_size.to_bytes(8, "big"))
        digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def _verify_and_copy_plugin(
    plugin: Path,
    verified_root: Path,
    app: Path,
    verifier: Path,
    epoch: int,
) -> dict[str, object]:
    plugin = require_input_directory(plugin, ".battman")
    initial = json.loads(run([sys.executable, str(verifier), str(plugin)]).stdout)
    identifier = initial.get("pluginIdentifier")
    digest = initial.get("packageSHA256")
    if not isinstance(identifier, str) or not isinstance(digest, str) or len(digest) != 64:
        raise ReleaseError("portable plug-in verifier returned incomplete identity data")

    copied_transport = verified_root / f"{identifier}.battman"
    copy_tree_normalized(plugin, copied_transport, epoch)
    copied = json.loads(run([sys.executable, str(verifier), str(copied_transport)]).stdout)
    if copied.get("pluginIdentifier") != identifier or copied.get("packageSHA256") != digest:
        raise ReleaseError(f"plug-in changed while entering release staging: {identifier}")

    manifest = json.loads((copied_transport / "Manifest.json").read_text(encoding="utf-8"))
    payload = manifest.get("payload")
    if not isinstance(payload, dict) or payload.get("kind") != "bundle":
        raise ReleaseError("TrollStore sealed representation currently requires a bundle payload")
    logical_payload = payload.get("path")
    if (
        not isinstance(logical_payload, str)
        or PurePosixPath(logical_payload).parent != PurePosixPath(".")
        or not logical_payload.endswith(".bundle")
    ):
        raise ReleaseError("sealed bundle payload must be a package-root .bundle directory")
    transport_payload = copied_transport / logical_payload
    if not transport_payload.is_dir() or transport_payload.is_symlink():
        raise ReleaseError("verified bundle payload is absent from release staging")

    payload_destination = app / "PlugIns" / f"{identifier}.bundle"
    metadata_destination = app / "PluginManifests" / identifier
    copy_tree_normalized(transport_payload, payload_destination, epoch)
    copy_tree_normalized(copied_transport, metadata_destination, epoch)
    metadata_payload = metadata_destination / logical_payload
    remove_staged_tree(metadata_payload, metadata_destination)
    os.utime(metadata_destination, (epoch, epoch), follow_symlinks=False)

    sealed_digest = _logical_package_digest(
        metadata_destination, payload_destination, logical_payload
    )
    if sealed_digest != digest:
        raise ReleaseError(f"sealed representation changed signed package bytes: {identifier}")
    return {
        "pluginIdentifier": identifier,
        "packageSHA256": digest,
        "verifiedPublisherKeys": copied.get("verifiedPublisherKeys", []),
        "payloadPath": f"PlugIns/{identifier}.bundle",
        "metadataPath": f"PluginManifests/{identifier}",
    }


def main() -> int:
    arguments = _parse_arguments()
    epoch = source_date_epoch(arguments.source_date_epoch)
    version = require_version(arguments.version)
    output = require_new_output(arguments.output, ".tipa")
    report = require_new_output(arguments.report, ".json")
    if output.parent != report.parent:
        raise ReleaseError("TIPA and report outputs must share one existing parent")

    app_source = require_input_directory(arguments.app, ".app")
    app_info, _ = load_app_info(app_source)
    if app_source.name != "Battman.app":
        raise ReleaseError("TIPA input must be named Battman.app")
    if app_info.get("CFBundleShortVersionString") != version or app_info.get("CFBundleVersion") != version:
        raise ReleaseError("app bundle versions must exactly match --version")
    if app_info.get("CFBundleIdentifier") not in (
        "com.torrekie.Battman",
        "com.torrekie.Battman.Havoc",
    ):
        raise ReleaseError("unexpected Battman app bundle identifier")
    if arguments.require_release and app_info.get("BTBuildConfiguration") != "Release":
        raise ReleaseError("release TIPA input is not marked BTBuildConfiguration=Release")
    for reserved in ("PlugIns", "PluginManifests"):
        if (app_source / reserved).exists() or (app_source / reserved).is_symlink():
            raise ReleaseError(f"base app already contains reserved sealed plug-in root: {reserved}")

    repo_root = Path(__file__).resolve().parents[2]
    verifier = repo_root / "PluginSDK/Tools/Package/verify-plugin-package.py"
    temporary = temporary_sibling(output.parent, ".battman-tipa-")
    output_installed = False
    report_installed = False
    try:
        payload_root = temporary / "archive/Payload"
        app_destination = payload_root / "Battman.app"
        copy_tree_normalized(app_source, app_destination, epoch)

        removed_outer_signature = False
        outer_signature = app_destination / "_CodeSignature"
        if outer_signature.exists() or outer_signature.is_symlink():
            if not outer_signature.is_dir() or outer_signature.is_symlink():
                raise ReleaseError("outer app _CodeSignature is not a safe directory")
            remove_staged_tree(outer_signature, app_destination)
            removed_outer_signature = True
            os.utime(app_destination, (epoch, epoch), follow_symlinks=False)

        plugins: list[dict[str, object]] = []
        seen: set[str] = set()
        verified_root = temporary / "verified"
        verified_root.mkdir(mode=0o755)
        os.utime(verified_root, (epoch, epoch), follow_symlinks=False)
        for plugin in arguments.plugin:
            record = _verify_and_copy_plugin(
                plugin, verified_root, app_destination, verifier, epoch
            )
            identifier = str(record["pluginIdentifier"])
            if identifier in seen:
                raise ReleaseError(f"duplicate TIPA plug-in identifier: {identifier}")
            seen.add(identifier)
            plugins.append(record)
        if plugins:
            for directory in (app_destination / "PlugIns", app_destination / "PluginManifests"):
                os.chmod(directory, 0o755)
                os.utime(directory, (epoch, epoch), follow_symlinks=False)
            os.utime(app_destination, (epoch, epoch), follow_symlinks=False)
        plugins.sort(key=lambda item: str(item["pluginIdentifier"]).encode("utf-8"))

        archive_candidate = temporary / output.name
        deterministic_zip(temporary / "archive", archive_candidate, epoch)
        report_value = {
            "schemaVersion": 1,
            "artifact": output.name,
            "artifactSHA256": sha256_file(archive_candidate),
            "appBundleIdentifier": app_info["CFBundleIdentifier"],
            "appTreeSHA256": tree_digest(app_destination),
            "embeddedPlugins": plugins,
            "outerCodeSignatureRemoved": removed_outer_signature,
            "requiresOuterResign": True,
            "requiresExplicitInstall": True,
            "signedByThisTool": False,
            "installedByThisTool": False,
            "sourceDateEpoch": epoch,
            "version": version,
        }
        report_candidate = temporary / report.name
        write_json(report_candidate, report_value, epoch)
        os.replace(archive_candidate, output)
        output_installed = True
        os.replace(report_candidate, report)
        report_installed = True
        os.utime(output, (epoch, epoch), follow_symlinks=False)
        os.utime(report, (epoch, epoch), follow_symlinks=False)
    except Exception:
        if report_installed and report.is_file():
            report.unlink()
        if output_installed and output.is_file():
            output.unlink()
        raise
    finally:
        if temporary.exists():
            remove_staged_tree(temporary, output.parent)
    print(output)
    print(report)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
