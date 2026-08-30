#!/usr/bin/env python3
"""Strictly inspect Battman Debian, TIPA and SDK release artifacts."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from compatibility_matrix import load_compatibility_matrix
from debian_archive import data_members, extract_data, read_ar_members, read_control
from host_build_identity import require_embedded_identity, require_git_object_id
from release_common import (
    PLUGIN_SDK_MIT_LICENSE_SHA256,
    ReleaseError,
    require_git_commit,
    require_identifier,
    require_new_output,
    require_package_version,
    require_plugin_sdk_license_data,
    require_version,
    run,
    sha256_file,
    source_date_epoch,
    write_json,
)
from plugin_release_pins import read_plugin_package_release_identity


DEB_LAYOUTS = {
    "rooted": ("iphoneos-arm", "./Applications/Battman.app/"),
    "rootless": ("iphoneos-arm64", "./var/jb/Applications/Battman.app/"),
}
PLUGIN_DEB_LAYOUTS = {
    "rooted": ("iphoneos-arm", "./Library/Battman/PlugIns/"),
    "rootless": ("iphoneos-arm64", "./var/jb/Library/Battman/PlugIns/"),
}
CONTROL_LINE = re.compile(r"^([A-Za-z0-9-]+):[ ]?(.*)$")


def _safe_archive_name(name: str) -> PurePosixPath:
    if not name or name.startswith("/") or "\\" in name or "\x00" in name:
        raise ReleaseError(f"unsafe archive path: {name!r}")
    pure = PurePosixPath(name.rstrip("/"))
    if any(part in ("", ".", "..") for part in pure.parts):
        raise ReleaseError(f"unsafe archive path component: {name!r}")
    return pure


def _parse_control(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    current: str | None = None
    for line in text.splitlines():
        match = CONTROL_LINE.fullmatch(line)
        if match:
            current = match.group(1)
            if current in values:
                raise ReleaseError(f"duplicate Debian control field: {current}")
            values[current] = match.group(2)
        elif line.startswith(" ") and current:
            values[current] += "\n" + line
        else:
            raise ReleaseError("malformed Debian control metadata")
    return values


def _inspect_macho(executable: Path) -> dict[str, object]:
    file_output = run(["file", str(executable)]).stdout.strip()
    if "Mach-O 64-bit executable arm64" not in file_output:
        raise ReleaseError(f"app executable is not a thin arm64 Mach-O executable: {file_output}")
    load_commands = run(["otool", "-l", str(executable)]).stdout
    if "platform 2" not in load_commands and "cmd LC_VERSION_MIN_IPHONEOS" not in load_commands:
        raise ReleaseError("app executable has no iOS platform load command")
    signature_match = re.search(
        r"cmd LC_CODE_SIGNATURE\s+cmdsize \d+\s+dataoff \d+\s+datasize ([1-9][0-9]*)",
        load_commands,
    )
    executable_signature = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2", str(executable)],
        text=True,
        capture_output=True,
    )
    bundle_signature = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2", str(executable.parent)],
        text=True,
        capture_output=True,
    )
    ldid_path = shutil.which("ldid")
    ldid_signature_valid = False
    if ldid_path:
        ldid_signature_valid = subprocess.run(
            [ldid_path, "-h", str(executable)],
            text=True,
            capture_output=True,
        ).returncode == 0
    inspectable = executable_signature.returncode == 0 or ldid_signature_valid
    return {
        "format": "Mach-O 64-bit executable arm64",
        "platform": "iOS",
        "executableCodeSignatureValid": executable_signature.returncode == 0,
        "bundleResourceSealValid": bundle_signature.returncode == 0,
        "embeddedCodeSignaturePresent": signature_match is not None,
        "ldidSignatureInspectable": ldid_signature_valid,
        "platformSignatureInspectable": inspectable,
    }


def inspect_deb(
    path: Path,
    flavor: str,
    version: str,
    package: str,
    *,
    allow_debug: bool = False,
    commit: str | None = None,
    source_tree: str | None = None,
) -> dict[str, object]:
    path = path.resolve()
    if not path.is_file() or path.is_symlink() or path.suffix != ".deb":
        raise ReleaseError(f"Debian artifact is not a regular .deb: {path}")
    architecture, install_root = DEB_LAYOUTS[flavor]
    archive_members = read_ar_members(path)
    try:
        control_text = read_control(archive_members).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseError("Debian control metadata is not valid UTF-8") from error
    control = _parse_control(control_text)
    expected = {"Package": package, "Version": version, "Architecture": architecture}
    for key, value in expected.items():
        if control.get(key) != value:
            raise ReleaseError(f"{flavor} Debian {key} mismatch")
    with tempfile.TemporaryDirectory(prefix="battman-payload-inspect-") as temporary:
        extraction = Path(temporary) / "payload"
        extract_data(archive_members, extraction)
        app_relative = "Applications/Battman.app" if flavor == "rooted" else "var/jb/Applications/Battman.app"
        app = extraction / app_relative
        try:
            info = plistlib.loads((app / "Info.plist").read_bytes())
        except (OSError, plistlib.InvalidFileException) as error:
            raise ReleaseError(f"{flavor} Debian contains an invalid app Info.plist") from error
        if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
            raise ReleaseError(f"{flavor} Debian app version mismatch")
        if info.get("CFBundleIdentifier") not in ("com.torrekie.Battman", "com.torrekie.Battman.Havoc"):
            raise ReleaseError(f"{flavor} Debian app identifier mismatch")
        if not allow_debug and info.get("BTBuildConfiguration") != "Release":
            raise ReleaseError(f"{flavor} Debian app is not marked as a Release build")
        if commit and info.get("GIT_COMMIT_HASH") not in (commit, commit[:7], commit[:8], commit[:9], commit[:10], commit[:11], commit[:12]):
            raise ReleaseError(f"{flavor} Debian source commit does not match the release commit")
        executable_name = info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or "/" in executable_name:
            raise ReleaseError(f"{flavor} Debian app executable metadata is invalid")
        executable = app / executable_name
        build_identity = require_embedded_identity(
            executable,
            version=version,
            configuration=info.get("BTBuildConfiguration"),
            product_identifier=info.get("CFBundleIdentifier"),
            source_commit=commit,
            source_tree=source_tree,
            source_dirty=False if not allow_debug else None,
        )
        macho = _inspect_macho(executable)
        if not allow_debug and not macho["platformSignatureInspectable"]:
            raise ReleaseError(f"{flavor} Debian app code signature is not inspectable by codesign or ldid")
    contents = data_members(archive_members)
    names: list[str] = []
    expected_root = install_root.rstrip("/")
    ancestors = {
        "rooted": {".", "./Applications"},
        "rootless": {".", "./var", "./var/jb", "./var/jb/Applications"},
    }[flavor]
    for member in contents:
        name = member.name
        normalized = name[2:] if name.startswith("./") else name
        normalized = normalized.rstrip("/")
        canonical = "." if normalized in ("", ".") else "./" + normalized
        if canonical != ".":
            _safe_archive_name(normalized)
        if canonical not in ancestors and not (
            canonical == expected_root or canonical.startswith(expected_root + "/")
        ):
            raise ReleaseError(f"unexpected {flavor} Debian payload path: {name}")
        names.append(canonical)
    if not names or expected_root not in names:
        raise ReleaseError(f"{flavor} Debian app root is missing")
    return {
        "kind": f"host-debian-{flavor}",
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "package": package,
        "version": version,
        "architecture": architecture,
        "installRoot": "/" + install_root[2:].rstrip("/"),
        "payloadEntryCount": len(names),
        "maintainerScriptsAllowed": False,
        "appBuildConfiguration": info.get("BTBuildConfiguration", "unmarked"),
        "appSourceCommit": info.get("GIT_COMMIT_HASH", ""),
        "appBuildIdentity": build_identity,
        "machO": macho,
    }


def inspect_plugin_deb(
    path: Path,
    flavor: str,
    version: str,
    package: str,
    host_version: str,
) -> dict[str, object]:
    path = path.resolve()
    if not path.is_file() or path.is_symlink() or path.suffix != ".deb":
        raise ReleaseError(f"plug-in Debian artifact is not a regular .deb: {path}")
    architecture, install_root = PLUGIN_DEB_LAYOUTS[flavor]
    archive_members = read_ar_members(path)
    try:
        control_text = read_control(archive_members).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseError("plug-in Debian control metadata is not valid UTF-8") from error
    control = _parse_control(control_text)
    expected = {"Package": package, "Version": version, "Architecture": architecture}
    for key, value in expected.items():
        if control.get(key) != value:
            raise ReleaseError(f"{flavor} plug-in Debian {key} mismatch")
    if control.get("Depends") != f"com.torrekie.battman (>= {host_version})":
        raise ReleaseError(f"{flavor} plug-in Debian host dependency mismatch")

    contents = data_members(archive_members)
    expected_package_root = install_root + f"{package}.battman"
    ancestors = {
        "rooted": {".", "./Library", "./Library/Battman", "./Library/Battman/PlugIns"},
        "rootless": {
            ".", "./var", "./var/jb", "./var/jb/Library",
            "./var/jb/Library/Battman", "./var/jb/Library/Battman/PlugIns",
        },
    }[flavor]
    names: list[str] = []
    for member in contents:
        normalized = member.name[2:] if member.name.startswith("./") else member.name
        normalized = normalized.rstrip("/")
        canonical = "." if normalized in ("", ".") else "./" + normalized
        if canonical != ".":
            _safe_archive_name(normalized)
        if canonical not in ancestors and not (
            canonical == expected_package_root
            or canonical.startswith(expected_package_root + "/")
        ):
            raise ReleaseError(f"unexpected {flavor} plug-in Debian payload path: {member.name}")
        names.append(canonical)
    if expected_package_root not in names:
        raise ReleaseError(f"{flavor} plug-in Debian package root is missing")

    with tempfile.TemporaryDirectory(prefix="battman-plugin-deb-inspect-") as temporary:
        extraction = Path(temporary) / "payload"
        extract_data(archive_members, extraction)
        relative = expected_package_root[2:]
        plugin = extraction / relative
        verifier = Path(__file__).resolve().parents[2] / "PluginSDK/Tools/Package/verify-plugin-package.py"
        verification = json.loads(run([sys.executable, str(verifier), str(plugin)]).stdout)
        if verification.get("pluginIdentifier") != package:
            raise ReleaseError(f"{flavor} plug-in Debian payload identity mismatch")

    return {
        "kind": f"plugin-debian-{flavor}",
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "package": package,
        "version": version,
        "hostMinimumVersion": host_version,
        "architecture": architecture,
        "installRoot": "/" + expected_package_root[2:],
        "payloadEntryCount": len(names),
        "maintainerScriptsAllowed": False,
        "portablePackageVerification": "passed",
    }


def inspect_plugin_transport_archive(
    path: Path,
    version: str,
    package: str,
    *,
    artifact_kind: str = "plugin-transport",
    activation_policy: str = "official-delegation-required",
) -> dict[str, object]:
    path = path.resolve()
    expected_name = f"{package}_{version}.battman.zip"
    if not path.is_file() or path.is_symlink() or path.name != expected_name:
        raise ReleaseError(f"plug-in transport archive must be named {expected_name}")
    expected_root = f"{package}.battman"
    names: set[str] = set()
    with zipfile.ZipFile(path) as archive:
        records: list[tuple[zipfile.ZipInfo, PurePosixPath, int]] = []
        for info in archive.infolist():
            pure = _safe_archive_name(info.filename)
            name = pure.as_posix()
            if name in names:
                raise ReleaseError(f"duplicate plug-in transport path: {name}")
            names.add(name)
            if pure.parts[0] != expected_root:
                raise ReleaseError(f"plug-in transport escaped its canonical package root: {name}")
            mode = (info.external_attr >> 16) & 0xFFFF
            if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)) or stat.S_ISLNK(mode) or mode & (
                stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX
            ):
                raise ReleaseError(f"unsafe plug-in transport entry mode: {name}")
            records.append((info, pure, mode))
        required = {
            f"{expected_root}/Info.plist",
            f"{expected_root}/Manifest.json",
        }
        if not required <= names or not any(
            name.startswith(f"{expected_root}/Signatures/") for name in names
        ):
            raise ReleaseError("plug-in transport archive is missing signed package metadata")
        with tempfile.TemporaryDirectory(prefix="battman-plugin-transport-inspect-") as temporary:
            extraction = Path(temporary)
            directories: list[Path] = []
            for info, pure, mode in records:
                destination = extraction.joinpath(*pure.parts)
                if stat.S_ISDIR(mode):
                    destination.mkdir(mode=0o755, parents=True, exist_ok=True)
                    directories.append(destination)
                    continue
                destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                with archive.open(info, "r") as source, destination.open("xb") as output:
                    shutil.copyfileobj(source, output, length=64 * 1024)
                destination.chmod(0o755 if mode & 0o111 else 0o644)
            for directory in directories:
                directory.chmod(0o755)
            plugin = Path(temporary) / expected_root
            verifier = Path(__file__).resolve().parents[2] / "PluginSDK/Tools/Package/verify-plugin-package.py"
            verification = json.loads(run([sys.executable, str(verifier), str(plugin)]).stdout)
            if verification.get("pluginIdentifier") != package:
                raise ReleaseError("plug-in transport archive payload identity mismatch")
            signed_identity = read_plugin_package_release_identity(
                plugin, "inspected signed plug-in transport"
            )
            if signed_identity["pluginIdentifier"] != package or \
                    signed_identity["displayVersion"] != version:
                raise ReleaseError("plug-in transport archive release identity mismatch")
    return {
        "kind": artifact_kind,
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "package": package,
        "version": version,
        "archiveRoot": expected_root,
        "payloadEntryCount": len(names),
        "portablePackageVerification": "passed",
        "packageSHA256": verification.get("packageSHA256"),
        "activationPolicy": activation_policy,
        "displayVersion": signed_identity["displayVersion"],
        "buildVersion": signed_identity["buildVersion"],
        "releaseSequence": signed_identity["releaseSequence"],
    }


def inspect_compatibility_matrix(path: Path, version: str) -> dict[str, object]:
    path = path.resolve()
    if path.name != "compatibility-matrix.json":
        raise ReleaseError("release compatibility matrix must use its canonical filename")
    value = load_compatibility_matrix(path, version)
    statuses: dict[str, int] = {}
    for item in value["evidence"]:
        statuses[item["status"]] = statuses.get(item["status"], 0) + 1
    return {
        "kind": "compatibility-matrix",
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "version": version,
        "minimumIOSVersion": value["host"]["minimumIOSVersion"],
        "declaredHardwareBaseline": value["host"]["declaredHardwareBaseline"],
        "fullDeviceMatrixCompleted": value["host"]["fullDeviceMatrixCompleted"],
        "trollStoreDataDirectoryNativeLoadingClaimed":
            value["validationPolicy"]["trollStoreDataDirectoryNativeLoadingClaimed"],
        "evidenceStatusCounts": statuses,
    }


def inspect_tipa(
    path: Path,
    version: str,
    *,
    allow_debug: bool = False,
    commit: str | None = None,
    source_tree: str | None = None,
) -> dict[str, object]:
    path = path.resolve()
    if not path.is_file() or path.is_symlink() or path.suffix != ".tipa":
        raise ReleaseError("TIPA artifact is not a regular .tipa")
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names: set[str] = set()
        for info in infos:
            pure = _safe_archive_name(info.filename)
            normalized = pure.as_posix()
            if normalized in names:
                raise ReleaseError(f"duplicate TIPA path: {normalized}")
            names.add(normalized)
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode) or (mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID)):
                raise ReleaseError(f"unsafe TIPA entry mode: {normalized}")
            if pure.parts not in (("Payload",), ("Payload", "Battman.app")) and \
                    pure.parts[:2] != ("Payload", "Battman.app"):
                raise ReleaseError(f"TIPA entry is outside Payload/Battman.app: {normalized}")
        info_name = "Payload/Battman.app/Info.plist"
        if info_name not in names:
            raise ReleaseError("TIPA app Info.plist is absent")
        info = plistlib.loads(archive.read(info_name))
        if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
            raise ReleaseError("TIPA app version mismatch")
        if not allow_debug and info.get("BTBuildConfiguration") != "Release":
            raise ReleaseError("TIPA app is not marked as a Release build")
        if commit and info.get("GIT_COMMIT_HASH") not in (commit, commit[:7], commit[:8], commit[:9], commit[:10], commit[:11], commit[:12]):
            raise ReleaseError("TIPA source commit does not match the release commit")
        if "Payload/Battman.app/_CodeSignature/CodeResources" in names:
            raise ReleaseError("TIPA retained an invalid copied outer CodeResources seal")
        plugin_ids = sorted(
            {name.split("/")[3] for name in names if name.startswith("Payload/Battman.app/PluginManifests/") and len(name.split("/")) > 4},
            key=lambda value: value.encode("utf-8"),
        )
        for identifier in plugin_ids:
            require_identifier(identifier, "sealed plug-in identifier")
            payload_prefix = f"Payload/Battman.app/PlugIns/{identifier}.bundle/"
            metadata_prefix = f"Payload/Battman.app/PluginManifests/{identifier}/"
            if not any(name.startswith(payload_prefix) for name in names) or not any(name.startswith(metadata_prefix) for name in names):
                raise ReleaseError(f"sealed plug-in pair is incomplete: {identifier}")
        with tempfile.TemporaryDirectory(prefix="battman-tipa-inspect-") as temporary:
            archive.extractall(temporary)
            app = Path(temporary) / "Payload/Battman.app"
            executable_name = info.get("CFBundleExecutable")
            if not isinstance(executable_name, str) or "/" in executable_name:
                raise ReleaseError("TIPA app executable metadata is invalid")
            executable = app / executable_name
            build_identity = require_embedded_identity(
                executable,
                version=version,
                configuration=info.get("BTBuildConfiguration"),
                product_identifier=info.get("CFBundleIdentifier"),
                source_commit=commit,
                source_tree=source_tree,
                source_dirty=False if not allow_debug else None,
            )
            macho = _inspect_macho(executable)
            # Replacement TIPAs intentionally require the installer (for
            # example TrollStore) to sign the outer app.  build-tipa.py removes
            # the resource seal, so the executable may retain an inert
            # LC_CODE_SIGNATURE load command even though no verifiable outer
            # signature is available.  Do not require the optional `ldid` tool
            # here; the nested plug-in signatures and all build identity checks
            # above remain mandatory.  Debian artifacts retain their separate
            # strict platform-signature check in inspect_deb().
            for identifier in plugin_ids:
                nested = app / "PlugIns" / f"{identifier}.bundle"
                signature = subprocess.run(
                    ["codesign", "--verify", "--strict", "--verbose=2", str(nested)],
                    text=True,
                    capture_output=True,
                )
                if signature.returncode != 0:
                    detail = (signature.stderr or signature.stdout).strip()
                    raise ReleaseError(f"nested plug-in code signature is invalid: {identifier}: {detail}")
    return {
        "kind": "trollstore-replacement-tipa",
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "version": version,
        "sealedPluginIdentifiers": plugin_ids,
        "requiresOuterResign": True,
        "appBuildConfiguration": info.get("BTBuildConfiguration", "unmarked"),
        "appSourceCommit": info.get("GIT_COMMIT_HASH", ""),
        "appBuildIdentity": build_identity,
        "machO": macho,
    }


def inspect_sdk(path: Path, version: str, allow_license_pending: bool) -> dict[str, object]:
    path = path.resolve()
    if not path.is_file() or path.is_symlink() or not path.name.endswith(".tar.gz"):
        raise ReleaseError("SDK artifact is not a regular .tar.gz")
    prefix = f"BattmanPluginSDK-{version}"
    required = {f"{prefix}/include/BattmanPluginABI.h", f"{prefix}/SDKContractV1.json", f"{prefix}/VERSION"}
    names: set[str] = set()
    license_data: bytes | None = None
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            pure = _safe_archive_name(member.name)
            name = pure.as_posix()
            if name in names:
                raise ReleaseError(f"duplicate SDK archive path: {name}")
            names.add(name)
            if pure.parts[0] != prefix or member.issym() or member.islnk() or not (member.isdir() or member.isfile()):
                raise ReleaseError(f"unsafe SDK archive entry: {name}")
            if member.uid != 0 or member.gid != 0 or member.mode & (stat.S_IWGRP | stat.S_IWOTH | stat.S_ISUID | stat.S_ISGID):
                raise ReleaseError(f"unsafe SDK archive metadata: {name}")
            if name == f"{prefix}/LICENSE":
                if not member.isfile() or member.size > 16 * 1024:
                    raise ReleaseError("SDK archive license is not one bounded regular file")
                stream = archive.extractfile(member)
                if stream is None:
                    raise ReleaseError("SDK archive license could not be read")
                license_data = stream.read(16 * 1024 + 1)
    if not required.issubset(names):
        raise ReleaseError("SDK archive is missing its frozen v1 public contract")
    has_license = license_data is not None
    if has_license:
        require_plugin_sdk_license_data(license_data, "SDK archive LICENSE")
    if not has_license and not allow_license_pending:
        raise ReleaseError("SDK archive has no owner-approved public-distribution license")
    result: dict[str, object] = {
        "kind": "plugin-sdk",
        "name": path.name,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
        "version": version,
        "entryCount": len(names),
        "licenseApproved": has_license,
        "distributionStatus": "public-ready" if has_license else "internal-license-pending",
    }
    if has_license:
        result.update({
            "licenseIdentifier": "MIT",
            "licenseSHA256": PLUGIN_SDK_MIT_LICENSE_SHA256,
        })
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rooted-deb", required=True, type=Path)
    parser.add_argument("--rootless-deb", required=True, type=Path)
    parser.add_argument("--tipa", required=True, type=Path)
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument(
        "--plugin-deb",
        action="append",
        default=[],
        nargs=4,
        metavar=("FLAVOR", "VERSION", "PACKAGE", "PATH"),
        help="inspect one rooted/rootless official plug-in Debian add-on",
    )
    parser.add_argument(
        "--plugin-transport",
        action="append",
        default=[],
        nargs=3,
        metavar=("VERSION", "PACKAGE", "PATH"),
        help="inspect one downloadable official .battman.zip transport",
    )
    parser.add_argument(
        "--sdk-example-transport",
        required=True,
        nargs=3,
        metavar=("VERSION", "PACKAGE", "PATH"),
        help="inspect the separately signed third-party SDK example transport",
    )
    parser.add_argument("--compatibility-matrix", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--package", default="com.torrekie.battman")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--allow-license-pending", action="store_true")
    parser.add_argument("--allow-debug", action="store_true")
    parser.add_argument("--commit")
    parser.add_argument("--source-tree")
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    version = require_version(arguments.version)
    package = require_identifier(arguments.package, "host package identifier")
    commit = require_git_commit(arguments.commit) if arguments.commit else None
    source_tree = (
        require_git_object_id(arguments.source_tree, "source tree")
        if arguments.source_tree else None
    )
    output = require_new_output(arguments.output, ".json")
    artifacts = [
        inspect_deb(arguments.rooted_deb, "rooted", version, package,
            allow_debug=arguments.allow_debug, commit=commit, source_tree=source_tree),
        inspect_deb(arguments.rootless_deb, "rootless", version, package,
            allow_debug=arguments.allow_debug, commit=commit, source_tree=source_tree),
        inspect_tipa(arguments.tipa, version,
            allow_debug=arguments.allow_debug, commit=commit, source_tree=source_tree),
        inspect_sdk(arguments.sdk, version, arguments.allow_license_pending),
        inspect_compatibility_matrix(arguments.compatibility_matrix, version),
    ]
    seen_plugin_artifacts: set[tuple[str, str]] = set()
    for flavor, plugin_version, plugin_identifier, raw_path in arguments.plugin_deb:
        if flavor not in PLUGIN_DEB_LAYOUTS:
            raise ReleaseError(f"unknown plug-in Debian flavor: {flavor}")
        plugin_identifier = require_identifier(plugin_identifier, "plug-in package identifier")
        plugin_version = require_package_version(plugin_version, "plug-in Debian version")
        key = (flavor, plugin_identifier)
        if key in seen_plugin_artifacts:
            raise ReleaseError(f"duplicate plug-in Debian inspection input: {flavor} {plugin_identifier}")
        seen_plugin_artifacts.add(key)
        artifacts.append(inspect_plugin_deb(
            Path(raw_path), flavor, plugin_version, plugin_identifier, version
        ))
    seen_plugin_transports: set[str] = set()
    for plugin_version, plugin_identifier, raw_path in arguments.plugin_transport:
        plugin_identifier = require_identifier(plugin_identifier, "plug-in transport identifier")
        plugin_version = require_package_version(plugin_version, "plug-in transport version")
        if plugin_identifier in seen_plugin_transports:
            raise ReleaseError(f"duplicate plug-in transport inspection input: {plugin_identifier}")
        seen_plugin_transports.add(plugin_identifier)
        artifacts.append(inspect_plugin_transport_archive(
            Path(raw_path), plugin_version, plugin_identifier
        ))
    sdk_example_version, sdk_example_identifier, sdk_example_path = arguments.sdk_example_transport
    sdk_example_identifier = require_identifier(
        sdk_example_identifier, "SDK example transport identifier"
    )
    sdk_example_version = require_package_version(
        sdk_example_version, "SDK example transport version"
    )
    if sdk_example_identifier in seen_plugin_transports:
        raise ReleaseError("SDK example transport overlaps an official plug-in transport")
    artifacts.append(inspect_plugin_transport_archive(
        Path(sdk_example_path), sdk_example_version, sdk_example_identifier,
        artifact_kind="sdk-example-transport",
        activation_policy="third-party-explicit-approval-required",
    ))
    value = {
        "schemaVersion": 1,
        "status": "passed",
        "version": version,
        "sourceDateEpoch": epoch,
        "artifacts": artifacts,
        "limitations": [
            "Static local inspection does not prove installation on a rooted/rootless device.",
            "Replacement TIPA requires outer signing during an explicit TrollStore install.",
            "Community-reported device coverage is not an independently completed device matrix.",
        ],
    }
    write_json(output, value, epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, plistlib.InvalidFileException, tarfile.TarError, zipfile.BadZipFile, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
