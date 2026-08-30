#!/usr/bin/env python3
"""Atomically assemble and inspect the complete Battman release matrix.

Strict mode is deliberately non-publishing but release-qualified. The explicit
engineering-candidate mode relaxes tag, dirty-tree, Release-mark, and production
trust gates so the pipeline can be tested before production inputs exist.
Strict assembly accepts only the reviewed checksum public key and emits a
candidate awaiting its detached offline signature.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    remove_staged_tree,
    require_git_commit,
    require_identifier,
    require_new_output,
    require_plugin_sdk_license,
    require_version,
    run,
    source_date_epoch,
    temporary_sibling,
    tree_digest,
    write_normalized,
)
from official_trust import require_official_plugins, validate_official_trust
from compatibility_matrix import validate_repository_compatibility_matrix
from host_build_identity import (
    require_embedded_identity,
    require_product_identifier,
    require_git_object_id,
)
from release_inputs import (
    require_tracked_public_input,
)
from plugin_release_pins import (
    require_plugin_package_matches_pin,
    validate_signed_plugin_release_pins,
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--deb-app", required=True, type=Path)
    parser.add_argument("--tipa-app", required=True, type=Path)
    parser.add_argument("--plugin", action="append", default=[], type=Path)
    parser.add_argument("--sdk-example", required=True, type=Path)
    parser.add_argument("--sdk-example-key-id")
    parser.add_argument("--version", required=True)
    checksum_input = parser.add_mutually_exclusive_group(required=True)
    checksum_input.add_argument("--checksum-private-key", type=Path)
    checksum_input.add_argument("--checksum-public-key", type=Path)
    parser.add_argument("--checksum-key-id")
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--builder-id")
    parser.add_argument("--known-gate", action="append", default=[])
    parser.add_argument("--engineering-candidate", action="store_true")
    return parser.parse_args()


def _git(repo: Path, *arguments: str) -> str:
    return run(["git", "-C", str(repo), *arguments]).stdout.strip()


def _validate_source(repo: Path, version: str, epoch: int, engineering: bool) -> tuple[str, str]:
    commit = require_git_commit(_git(repo, "rev-parse", "HEAD"))
    source_tree = require_git_object_id(_git(repo, "rev-parse", "HEAD^{tree}"), "source tree")
    commit_epoch = int(_git(repo, "show", "-s", "--format=%ct", "HEAD"))
    if not engineering:
        if _git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
            raise ReleaseError("strict release assembly requires a clean checkout")
        tag = _git(repo, "describe", "--tags", "--exact-match", "HEAD")
        if tag != f"v{version}":
            raise ReleaseError(f"strict release assembly requires exact tag v{version}")
        if epoch != commit_epoch:
            raise ReleaseError("strict SOURCE_DATE_EPOCH must equal the tagged commit timestamp")
        require_plugin_sdk_license(repo / "PluginSDK/LICENSE")
    return commit, source_tree


def _require_app_identity(path: Path, version: str, commit: str, source_tree: str, engineering: bool,
                          expected_trust_digest: str | None = None,
                          required_content_markers: list[str] | None = None) -> None:
    path = path.expanduser().resolve()
    try:
        info = plistlib.loads((path / "Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise ReleaseError(f"invalid release app input: {path}") from error
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
        raise ReleaseError(f"release app version differs from {version}: {path}")
    configuration = info.get("BTBuildConfiguration")
    if not engineering and configuration != "Release":
        raise ReleaseError(f"strict release input is not Release-marked: {path}")
    if configuration not in ("Debug", "Release"):
        raise ReleaseError(f"release app build configuration is malformed: {path}")
    bundle_identifier = require_product_identifier(info.get("CFBundleIdentifier"))
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or "/" in executable_name:
        raise ReleaseError(f"strict release app executable metadata is malformed: {path}")
    executable = path / executable_name
    if not executable.is_file() or executable.is_symlink():
        raise ReleaseError(f"strict release app executable is missing or unsafe: {path}")
    acceptable_commits = {commit, *(commit[:length] for length in range(7, 13))}
    if not engineering and info.get("GIT_COMMIT_HASH") not in acceptable_commits:
        raise ReleaseError(f"strict release input does not identify source commit {commit}: {path}")
    require_embedded_identity(
        executable=executable,
        version=version,
        configuration=configuration,
        product_identifier=bundle_identifier,
        source_commit=commit,
        source_tree=source_tree,
        source_dirty=False if not engineering else None,
    )
    if expected_trust_digest is not None:
        bundled_trust = path / "PluginTrust"
        if not bundled_trust.is_dir() or bundled_trust.is_symlink() or tree_digest(bundled_trust) != expected_trust_digest:
            raise ReleaseError(f"app-bundled PluginTrust differs from the reviewed repository snapshot: {path}")
    if required_content_markers:
        if executable.stat().st_size > 128 * 1024 * 1024:
            raise ReleaseError(f"strict release app executable is missing or unsafe: {path}")
        encoded_markers = {
            marker: marker.encode("ascii", errors="strict") for marker in required_content_markers
        }
        found: set[str] = set()
        overlap_size = max(len(value) for value in encoded_markers.values()) - 1
        overlap = b""
        with executable.open("rb") as stream:
            while block := stream.read(64 * 1024):
                searchable = overlap + block
                found.update(
                    marker for marker, encoded in encoded_markers.items()
                    if marker not in found and encoded in searchable
                )
                if len(found) == len(encoded_markers):
                    break
                overlap = searchable[-overlap_size:] if overlap_size else b""
        missing = [marker for marker in required_content_markers if marker not in found]
        if missing:
            raise ReleaseError(
                "strict release app lacks selected Analytics or plug-in host content: "
                + ", ".join(missing)
            )


def _required_host_content_markers(repo: Path) -> list[str]:
    matrix_path = repo / "Packaging/Release/release-matrix.json"
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError("release matrix is missing or malformed") from error
    selection = matrix.get("officialPluginSelection")
    embedded = selection.get("embeddedAnalyticsCards") if isinstance(selection, dict) else None
    if not isinstance(embedded, list) or not embedded or any(
        not isinstance(value, str) for value in embedded
    ):
        raise ReleaseError("release matrix embedded Analytics selection is malformed")
    validated = [
        require_identifier(value, "embedded Analytics card identifier") for value in embedded
    ]
    if len(validated) != len(set(validated)):
        raise ReleaseError("release matrix embedded Analytics selection is duplicated")
    return [
        *sorted(validated, key=lambda value: value.encode("utf-8")),
        "com.torrekie.battman.analytics.card.v1",
        "BattmanPluginEntryPointV1",
        "BTPluginImportDidFinishNotification",
    ]


def _call(script: Path, arguments: list[str]) -> None:
    run([sys.executable, str(script), *arguments])


def _key_identifier(value: object, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(
        character not in "0123456789abcdef" for character in value
    ):
        raise ReleaseError(f"{label} must be a lowercase SHA-256 P-256 fingerprint")
    return value


def _plugin_release_identity(
    plugin: Path, label: str = "plug-in"
) -> tuple[str, str, str]:
    try:
        manifest = json.loads((plugin / "Manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError(f"invalid {label} manifest: {plugin}") from error
    identifier = manifest.get("pluginIdentifier")
    version = manifest.get("displayVersion")
    publisher = manifest.get("publisher")
    primary_key_identifier = (
        publisher.get("primaryKeyIdentifier") if isinstance(publisher, dict) else None
    )
    if not isinstance(identifier, str) or not isinstance(version, str):
        raise ReleaseError(f"{label} release identity is incomplete: {plugin}")
    from release_common import require_identifier, require_package_version
    return (
        require_identifier(identifier, f"{label} identifier"),
        require_package_version(version, f"{label} version"),
        _key_identifier(primary_key_identifier, f"{label} primary publisher key identifier"),
    )


def _selected_official_plugin_identifiers(repo: Path) -> list[str]:
    matrix_path = repo / "Packaging/Release/release-matrix.json"
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError("release matrix is missing or malformed") from error
    selection = matrix.get("officialPluginSelection")
    identifiers = selection.get("separatelyShipped") if isinstance(selection, dict) else None
    if not isinstance(identifiers, list) or not identifiers:
        raise ReleaseError("release matrix has no selected official plug-ins")
    from release_common import require_identifier
    selected = [require_identifier(value, "selected official plug-in identifier")
                for value in identifiers if isinstance(value, str)]
    if len(selected) != len(identifiers) or len(set(selected)) != len(selected):
        raise ReleaseError("release matrix official plug-in selection is malformed or duplicated")
    return sorted(selected, key=lambda value: value.encode("utf-8"))


def _sdk_example_identifier(repo: Path) -> str:
    matrix_path = repo / "Packaging/Release/release-matrix.json"
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError("release matrix is missing or malformed") from error
    example = matrix.get("sdkExample")
    identifier = example.get("pluginIdentifier") if isinstance(example, dict) else None
    from release_common import require_identifier
    if not isinstance(identifier, str):
        raise ReleaseError("release matrix has no SDK example identifier")
    expected = {
        "pluginIdentifier": identifier,
        "signedPackageRequired": True,
        "publisherIdentityReviewRequired": True,
        "officialTrustDelegation": False,
        "rootedRootlessAddOns": False,
        "replacementTIPAInclusion": False,
        "activationPolicy": "third-party-explicit-approval-required",
    }
    if example != expected:
        raise ReleaseError("release matrix SDK example policy is malformed")
    return require_identifier(identifier, "SDK example identifier")


def main() -> int:
    arguments = _arguments()
    version = require_version(arguments.version)
    epoch = source_date_epoch(arguments.source_date_epoch)
    output = require_new_output(arguments.output_directory)
    repo = arguments.repo.expanduser().resolve()
    try:
        git_root = Path(_git(repo, "rev-parse", "--show-toplevel")).resolve()
    except ReleaseError as error:
        raise ReleaseError("--repo is not a Git worktree root") from error
    if git_root != repo:
        raise ReleaseError("--repo must be the exact Git worktree root")
    if (repo / "VERSION").read_text(encoding="utf-8").strip() != version:
        raise ReleaseError("repository VERSION differs from --version")
    # Readiness records are owner-local and intentionally absent from the
    # public checkout.  Release assembly validates the immutable compatibility
    # contract here; the separate owner-local readiness checker is responsible
    # for review/evidence gates and must not be inferred from this build.
    compatibility = validate_repository_compatibility_matrix(repo, version)
    commit, source_tree = _validate_source(repo, version, epoch, arguments.engineering_candidate)
    official_trust = None
    selected_official_identifiers = _selected_official_plugin_identifiers(repo)
    sdk_example_identifier = _sdk_example_identifier(repo)
    try:
        release_matrix = json.loads(
            (repo / "Packaging/Release/release-matrix.json").read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError("release matrix is missing or malformed") from error
    if not isinstance(release_matrix, dict):
        raise ReleaseError("release matrix must contain one JSON object")
    official_release_pins, sdk_example_release_pin = validate_signed_plugin_release_pins(
        repo, release_matrix
    )
    plugin_identities = [_plugin_release_identity(plugin) for plugin in arguments.plugin]
    sdk_example_identity = _plugin_release_identity(arguments.sdk_example, "SDK example")
    if sdk_example_identity[0] != sdk_example_identifier:
        raise ReleaseError("signed SDK example identity differs from the release matrix")
    require_plugin_package_matches_pin(
        arguments.sdk_example, sdk_example_release_pin, "signed SDK example"
    )
    if arguments.sdk_example_key_id:
        expected_sdk_example_key = _key_identifier(
            arguments.sdk_example_key_id, "SDK example publisher key identifier"
        )
        if sdk_example_identity[2] != expected_sdk_example_key:
            raise ReleaseError(
                "signed SDK example publisher differs from the reviewed fingerprint"
            )
    elif not arguments.engineering_candidate:
        raise ReleaseError(
            "strict release assembly requires the reviewed SDK example publisher fingerprint"
        )
    plugin_identifiers = sorted(
        (identifier for identifier, _, _ in plugin_identities),
        key=lambda value: value.encode("utf-8"),
    )
    if len(plugin_identifiers) != len(set(plugin_identifiers)):
        raise ReleaseError("official plug-in inputs contain a duplicate identifier")
    if sdk_example_identity[0] in plugin_identifiers:
        raise ReleaseError("SDK example must remain separate from official plug-in selection")
    if plugin_identifiers != selected_official_identifiers:
        raise ReleaseError("official plug-in inputs do not match the owner-approved release matrix")
    for plugin, (plugin_identifier, _, _) in zip(arguments.plugin, plugin_identities):
        require_plugin_package_matches_pin(
            plugin,
            official_release_pins[plugin_identifier],
            f"signed official plug-in {plugin_identifier}",
        )
    if not arguments.engineering_candidate:
        sys.path.insert(0, str(repo / "PluginSDK/Tools/Package"))
        official_trust_path = repo / "OfficialPlugins/Trust/PluginTrust"
        official_trust = validate_official_trust(official_trust_path)
        require_official_plugins(arguments.plugin, official_trust)
        require_tracked_public_input(repo, official_trust_path, "official trust snapshot")
        for plugin in arguments.plugin:
            require_tracked_public_input(repo, plugin, "official plug-in package")
        require_tracked_public_input(repo, arguments.sdk_example, "SDK example package")
    expected_trust_digest = official_trust["treeSHA256"] if official_trust else None
    required_host_content = (
        _required_host_content_markers(repo) if not arguments.engineering_candidate else None
    )
    _require_app_identity(arguments.deb_app, version, commit, source_tree, arguments.engineering_candidate,
                          expected_trust_digest, required_host_content)
    _require_app_identity(arguments.tipa_app, version, commit, source_tree, arguments.engineering_candidate,
                          expected_trust_digest, required_host_content)
    if arguments.engineering_candidate:
        if arguments.checksum_public_key:
            raise ReleaseError(
                "engineering candidates require an ephemeral checksum private key"
            )
        assert arguments.checksum_private_key is not None
        private_key = arguments.checksum_private_key.expanduser().resolve()
        if not private_key.is_file() or private_key.is_symlink():
            raise ReleaseError("checksum private key must be an existing regular file")
    else:
        if not arguments.checksum_public_key:
            raise ReleaseError(
                "strict release assembly accepts only the reviewed checksum public key"
            )
        if not arguments.checksum_key_id:
            raise ReleaseError(
                "strict release assembly requires the owner-approved checksum key fingerprint"
            )
        checksum_public_input = arguments.checksum_public_key.expanduser().resolve()
        if not checksum_public_input.is_file() or checksum_public_input.is_symlink():
            raise ReleaseError("checksum public key must be an existing regular file")

    scripts = repo / "Scripts/Release"
    temporary = temporary_sibling(output.parent, ".battman-release-")
    try:
        release = temporary / "release"
        release.mkdir(mode=0o755)
        rooted = release / f"com.torrekie.battman_{version}_iphoneos-arm.deb"
        rootless = release / f"com.torrekie.battman_{version}_iphoneos-arm64.deb"
        tipa = release / "Battman.tipa"
        tipa_report = release / "Battman.tipa.report.json"
        sdk = release / f"BattmanPluginSDK-{version}.tar.gz"
        compatibility_matrix = release / "compatibility-matrix.json"
        inspection = release / "artifact-inspection.json"
        notes = release / "release-notes.md"
        sbom = release / "release-sbom.cdx.json"
        provenance = release / "release-provenance.intoto.jsonl"
        manifest = release / "release-manifest.json"
        checksums = release / "SHA256SUMS"
        checksum_signature = release / "SHA256SUMS.p256.sig"
        checksum_public_key = release / "SHA256SUMS.p256.pub"

        common_epoch = ["--source-date-epoch", str(epoch)]
        host_common = ["--app", str(arguments.deb_app), "--version", version, *common_epoch]
        if not arguments.engineering_candidate:
            host_common.append("--require-release")
        _call(scripts / "build-host-deb.py", [*host_common, "--flavor", "rooted", "--output", str(rooted)])
        _call(scripts / "build-host-deb.py", [*host_common, "--flavor", "rootless", "--output", str(rootless)])

        tipa_arguments = [
            "--app", str(arguments.tipa_app), "--version", version,
            "--output", str(tipa), "--report", str(tipa_report), *common_epoch,
        ]
        if not arguments.engineering_candidate:
            tipa_arguments.append("--require-release")
        for plugin in arguments.plugin:
            tipa_arguments.extend(["--plugin", str(plugin)])
        _call(scripts / "build-tipa.py", tipa_arguments)

        plugin_debians: list[tuple[str, str, str, Path]] = []
        plugin_transports: list[tuple[str, str, Path]] = []
        plugin_records = sorted(
            zip(arguments.plugin, plugin_identities),
            key=lambda record: record[1][0].encode("utf-8"),
        )
        for plugin, (plugin_identifier, plugin_version, _) in plugin_records:
            transport = release / f"{plugin_identifier}_{plugin_version}.battman.zip"
            _call(scripts / "archive-plugin-package.py", [
                "--plugin", str(plugin), "--output", str(transport), *common_epoch,
            ])
            plugin_transports.append((plugin_version, plugin_identifier, transport))
            for flavor, architecture in (("rooted", "iphoneos-arm"), ("rootless", "iphoneos-arm64")):
                output_path = release / f"{plugin_identifier}_{plugin_version}_{architecture}.deb"
                _call(scripts / "build-plugin-deb.py", [
                    "--plugin", str(plugin),
                    "--flavor", flavor,
                    "--version", plugin_version,
                    "--host-version", version,
                    "--output", str(output_path),
                    *common_epoch,
                ])
                plugin_debians.append((flavor, plugin_version, plugin_identifier, output_path))

        sdk_example_version, sdk_example_identifier = (
            sdk_example_identity[1], sdk_example_identity[0]
        )
        sdk_example_transport = release / (
            f"{sdk_example_identifier}_{sdk_example_version}.battman.zip"
        )
        _call(scripts / "archive-plugin-package.py", [
            "--plugin", str(arguments.sdk_example),
            "--output", str(sdk_example_transport),
            *common_epoch,
        ])

        sdk_arguments = [
            "--sdk", str(repo / "PluginSDK"), "--version", version,
            "--output", str(sdk), *common_epoch,
        ]
        if arguments.engineering_candidate:
            sdk_arguments.append("--allow-license-pending")
        _call(scripts / "build-sdk-archive.py", sdk_arguments)
        write_normalized(
            compatibility_matrix,
            (repo / "Packaging/Release/compatibility-matrix.json").read_bytes(),
            epoch,
        )

        note_gates = list(arguments.known_gate)
        if arguments.engineering_candidate:
            note_gates.extend([
                "Engineering candidate only; the checkout was not required to be clean or exactly tagged.",
                "Production trust/signature inputs and owner release approvals remain unresolved; do not publish this candidate.",
            ])
        notes_arguments = [
            "--version", version, "--commit", commit, "--output", str(notes), *common_epoch,
        ]
        for gate in note_gates:
            notes_arguments.extend(["--known-gate", gate])
        _call(scripts / "generate-release-notes.py", notes_arguments)

        inspect_arguments = [
            "--rooted-deb", str(rooted), "--rootless-deb", str(rootless),
            "--tipa", str(tipa), "--sdk", str(sdk), "--version", version,
            "--compatibility-matrix", str(compatibility_matrix),
            "--sdk-example-transport", sdk_example_version,
            sdk_example_identifier, str(sdk_example_transport),
            "--commit", commit, "--output", str(inspection), *common_epoch,
        ]
        inspect_arguments.extend(["--source-tree", source_tree])
        for flavor, plugin_version, plugin_identifier, path in plugin_debians:
            inspect_arguments.extend([
                "--plugin-deb", flavor, plugin_version, plugin_identifier, str(path),
            ])
        for plugin_version, plugin_identifier, path in plugin_transports:
            inspect_arguments.extend([
                "--plugin-transport", plugin_version, plugin_identifier, str(path),
            ])
        if arguments.engineering_candidate:
            inspect_arguments.extend(["--allow-debug", "--allow-license-pending"])
        _call(scripts / "inspect-release-artifacts.py", inspect_arguments)

        core_assets = [
            rooted, rootless, tipa, tipa_report, sdk,
            *(record[3] for record in plugin_debians),
            *(record[2] for record in plugin_transports),
            sdk_example_transport,
            compatibility_matrix,
            inspection, notes,
        ]
        _call(scripts / "generate-sbom.py", [
            *sum((["--asset", str(path)] for path in core_assets), []),
            "--version", version, "--commit", commit, "--output", str(sbom), *common_epoch,
        ])
        builder = arguments.builder_id or (
            "urn:battman:local-engineering-candidate" if arguments.engineering_candidate
            else f"https://github.com/Torrekie/Battman/.github/workflows/release.yml@refs/tags/v{version}"
        )
        provenance_subjects = [*core_assets, sbom]
        _call(scripts / "generate-provenance.py", [
            *sum((["--asset", str(path)] for path in provenance_subjects), []),
            "--commit", commit, "--builder-id", builder,
            "--output", str(provenance), *common_epoch,
        ])
        manifest_arguments = [
            "--release-directory", str(release),
            "--release-matrix", str(repo / "Packaging/Release/release-matrix.json"),
            "--inspection", str(inspection),
            "--version", version,
            "--commit", commit,
            "--output", str(manifest),
            *common_epoch,
        ]
        if arguments.engineering_candidate:
            manifest_arguments.append("--engineering-candidate")
        else:
            manifest_arguments.append("--unsigned-candidate")
        _call(scripts / "generate-release-manifest.py", manifest_arguments)
        if arguments.engineering_candidate:
            public_key_arguments = [
                "--private-key", str(private_key), "--output", str(checksum_public_key),
                *common_epoch,
            ]
            if arguments.checksum_key_id:
                public_key_arguments.extend([
                    "--expected-key-id", arguments.checksum_key_id,
                ])
            _call(scripts / "export-checksum-public-key.py", public_key_arguments)
        else:
            _call(scripts / "inspect-checksum-public-key.py", [
                str(checksum_public_input),
                "--expected-key-id", arguments.checksum_key_id,
            ])
            write_normalized(checksum_public_key, checksum_public_input.read_bytes(), epoch)
        checksum_assets = [
            *provenance_subjects, provenance, manifest, checksum_public_key,
        ]
        _call(scripts / "generate-checksums.py", [
            *sum((["--asset", str(path)] for path in checksum_assets), []),
            "--output", str(checksums), *common_epoch,
        ])
        _call(scripts / "verify-checksums.py", [str(checksums)])
        if arguments.engineering_candidate:
            _call(scripts / "sign-checksums.py", [
                "--private-key", str(private_key), "--checksums", str(checksums),
                "--signature", str(checksum_signature), *common_epoch,
            ])
            _call(scripts / "sign-checksums.py", [
                "--public-key", str(checksum_public_key), "--checksums", str(checksums),
                "--signature", str(checksum_signature),
            ])
            _call(scripts / "verify-release-directory.py", [str(release)])
        else:
            _call(scripts / "verify-release-directory.py", [
                str(release), "--allow-missing-offline-signature",
            ])

        os.utime(release, (epoch, epoch), follow_symlinks=False)
        os.rename(release, output)
    finally:
        if temporary.exists():
            remove_staged_tree(temporary, output.parent)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, plistlib.InvalidFileException, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
