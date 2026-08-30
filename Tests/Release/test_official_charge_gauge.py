#!/usr/bin/env python3
"""Build and package the official Charge Gauge with ephemeral test identities."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Keep direct single-test runs as clean and repeatable as the release-suite
# wrapper. Some in-process inspection helpers launch SDK Python tools before
# this file's subprocess helper is involved.
sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/Release"))

from release_common import sha256_file  # noqa: E402
from release_inspection import inspect_plugin_deb  # noqa: E402


PLUGIN_ID = "com.torrekie.battman.plugin.charge-gauge"
CARD_ID = "com.torrekie.battman.plugin.charge-gauge.card"
EPOCH = "1700000000"
STRICT_COMMIT_DATE = "2023-11-14T22:13:20+00:00"
STRICT_SOURCE_PATHS = (
    Path("VERSION"),
    Path("Battman/Makefile"),
    Path("Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.m"),
    Path("OfficialPlugins/ChargeGauge"),
    Path("Packaging"),
    Path("PluginSDK"),
    Path("Scripts/Build"),
    Path("Scripts/Release"),
    Path("docs/plugin-security.md"),
    Path("docs/plugin-system.md"),
    Path("docs/release-process.md"),
    Path("Tests/Device/run-analytics-rooted-preflight.sh"),
    Path("Tests/Release/test_official_charge_gauge.py"),
    Path("Tests/Simulator/BTAnalyticsCardsScreenshotHarness.m"),
)
def run(
    *arguments: str,
    cwd: Path = ROOT,
    extra_environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra_environment:
        environment.update(extra_environment)
    result = subprocess.run(arguments, cwd=cwd, env=environment, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(arguments)}\n"
            f"{result.stderr or result.stdout}"
        )
    return result


def key(root: Path, name: str) -> tuple[Path, Path, str, bytes]:
    private = ec.generate_private_key(ec.SECP256R1())
    public = private.public_key()
    raw = public.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    identifier = hashlib.sha256(raw).hexdigest()
    private_path = root / f"{name}-private.pem"
    public_path = root / f"{name}-public.pem"
    private_path.write_bytes(private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ))
    private_path.chmod(0o600)
    public_path.write_bytes(public.public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ))
    return private_path, public_path, identifier, raw


def encrypted_key(root: Path, name: str) -> tuple[Path, Path, str, Path]:
    password = b"ephemeral-strict-release-test-password"
    private = ec.generate_private_key(ec.SECP256R1())
    public = private.public_key()
    raw = public.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    identifier = hashlib.sha256(raw).hexdigest()
    private_path = root / f"{name}-private-encrypted.pem"
    public_path = root / f"{name}-public.pem"
    password_path = root / f"{name}.password"
    private_path.write_bytes(private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.BestAvailableEncryption(password),
    ))
    private_path.chmod(0o600)
    public_path.write_bytes(public.public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ))
    password_path.write_bytes(password + b"\n")
    password_path.chmod(0o600)
    return private_path, public_path, identifier, password_path


def copy_fixture_path(destination: Path, relative: Path) -> None:
    source = ROOT / relative
    target = destination / relative
    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(
            source,
            target,
            ignore=shutil.ignore_patterns(
                ".DS_Store", "__pycache__", "*.pyc", "*.pyo", "Packages"
            ),
        )
    else:
        shutil.copy2(source, target)


def prepare_strict_source(
    destination: Path,
    official_package: Path,
    trust: Path,
    sdk_example: Path,
) -> str:
    destination.mkdir(mode=0o755)
    for relative in STRICT_SOURCE_PATHS:
        copy_fixture_path(destination, relative)

    official_destination = (
        destination / "OfficialPlugins/Packages" / f"{PLUGIN_ID}.battman"
    )
    official_destination.parent.mkdir(mode=0o755, parents=True)
    shutil.copytree(official_package, official_destination)
    trust_destination = destination / "OfficialPlugins/Trust/PluginTrust"
    trust_destination.parent.mkdir(mode=0o755, parents=True)
    shutil.copytree(trust, trust_destination)
    example_destination = (
        destination / "PluginSDK/Examples/Packages"
        / "com.torrekie.battman.example.analytics.battman"
    )
    example_destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    shutil.copytree(sdk_example, example_destination)

    run("git", "init", "-q", cwd=destination)
    run("git", "config", "user.name", "Battman strict release fixture", cwd=destination)
    run(
        "git", "config", "user.email", "strict-release-fixture@invalid.example",
        cwd=destination,
    )
    run("git", "add", "-A", cwd=destination)
    commit_environment = {
        "GIT_AUTHOR_DATE": STRICT_COMMIT_DATE,
        "GIT_COMMITTER_DATE": STRICT_COMMIT_DATE,
    }
    run(
        "git", "commit", "-q", "-m", "Create disposable strict release fixture",
        cwd=destination,
        extra_environment=commit_environment,
    )
    run("git", "tag", "v1.1.0", cwd=destination)
    commit = run("git", "rev-parse", "HEAD", cwd=destination).stdout.strip()
    assert run("git", "show", "-s", "--format=%ct", "HEAD", cwd=destination).stdout.strip() == EPOCH
    assert run("git", "describe", "--tags", "--exact-match", "HEAD", cwd=destination).stdout.strip() == "v1.1.0"
    assert not run(
        "git", "status", "--porcelain=v1", "--untracked-files=all", cwd=destination
    ).stdout
    return commit


def prepare_strict_app(
    destination: Path,
    trust: Path,
    source: Path,
) -> Path:
    destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    destination.mkdir(mode=0o755)
    sdk_root = run("xcrun", "--sdk", "iphoneos", "--show-sdk-path").stdout.strip()
    clang = run("xcrun", "--sdk", "iphoneos", "--find", "clang").stdout.strip()
    identity = destination.parent / "BattmanBuildIdentity.json"
    run(
        sys.executable, str(source / "Scripts/Build/generate-build-identity.py"),
        "--repo", str(source), "--version", "1.1.0",
        "--configuration", "Release",
        "--product-identifier", "com.torrekie.Battman",
        "--output", str(identity), cwd=source,
    )
    commit = run("git", "rev-parse", "HEAD", cwd=source).stdout.strip()
    run(
        clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk_root,
        "-DBATTMAN_STRICT_HOST_FIXTURE=1", "-Wl,-no_uuid",
        f"-Wl,-sectcreate,__TEXT,__btidentity,{identity}",
        "Tests/Release/Fixtures/MinimalAppMain.c", "-o", str(destination / "Battman"),
    )
    with (destination / "Info.plist").open("wb") as stream:
        plistlib.dump({
        "CFBundleExecutable": "Battman",
        "CFBundleIdentifier": "com.torrekie.Battman",
        "CFBundleShortVersionString": "1.1.0",
        "CFBundleVersion": "1.1.0",
        "BTBuildConfiguration": "Release",
        "GIT_COMMIT_HASH": commit,
    }, stream, sort_keys=True)
    shutil.copytree(trust, destination / "PluginTrust")
    run(
        "codesign", "--force", "--sign", "-", "--timestamp=none",
        "--identifier", "com.torrekie.Battman", str(destination),
    )
    run("codesign", "--verify", "--deep", "--strict", str(destination))
    return destination


def tree_bytes(root: Path) -> dict[str, tuple[int, bytes]]:
    result = {}
    for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
        if path.is_file():
            result[path.relative_to(root).as_posix()] = (path.stat().st_mode & 0o777, path.read_bytes())
    return result


def signed_package_variant(
    root: Path,
    name: str,
    manifest_path: Path,
    payload: Path,
    publisher_private: Path,
    publisher_public: Path,
    publisher_raw: Path,
    field: str,
    value: object,
) -> Path:
    variant_root = root / name
    variant_root.mkdir(mode=0o755)
    variant_payload = variant_root / payload.name
    shutil.copytree(payload, variant_payload)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest[field] = value
    if field in {"displayVersion", "buildVersion"}:
        info_path = variant_payload / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info_key = (
            "CFBundleShortVersionString" if field == "displayVersion" else "CFBundleVersion"
        )
        info[info_key] = value
        with info_path.open("wb") as stream:
            plistlib.dump(info, stream, sort_keys=True)
        run(
            "codesign", "--force", "--sign", "-", "--timestamp=none",
            "--identifier", manifest["pluginIdentifier"], str(variant_payload),
        )
    rendered_manifest = variant_root / "Manifest.json"
    rendered_manifest.write_text(
        json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    package = root / f"{name}.battman"
    run(
        sys.executable, "PluginSDK/Tools/Package/build-plugin-package.py",
        "--manifest-template", str(rendered_manifest),
        "--payload", str(variant_payload),
        "--publisher-public-key", str(publisher_raw),
        "--output", str(package),
    )
    run(
        sys.executable, "PluginSDK/Tools/Package/sign-plugin-package.py", str(package),
        "--private-key", str(publisher_private),
    )
    verification = json.loads(run(
        sys.executable, "PluginSDK/Tools/Package/verify-plugin-package.py", str(package),
        "--public-key", str(publisher_public),
    ).stdout)
    assert verification["pluginIdentifier"] == manifest["pluginIdentifier"]
    signed_manifest = json.loads((package / "Manifest.json").read_text(encoding="utf-8"))
    assert signed_manifest[field] == value
    return package


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="battman-official-charge-gauge-") as raw:
        temporary = Path(raw)
        build_a = temporary / "build-a"
        build_b = temporary / "build-b"
        for build in (build_a, build_b):
            run(
                "make", "-C", "OfficialPlugins/ChargeGauge",
                f"SDK_ROOT={ROOT / 'PluginSDK'}", f"BUILD_DIR={build}", "-j1", "all",
            )
        bundle_a = build_a / "BattmanChargeGauge.bundle"
        bundle_b = build_b / "BattmanChargeGauge.bundle"
        executable_a = bundle_a / "BattmanChargeGauge"
        executable_b = bundle_b / "BattmanChargeGauge"
        if sha256_file(executable_a) != sha256_file(executable_b):
            raise AssertionError("Charge Gauge native executable was not reproducible")
        if tree_bytes(bundle_a) != tree_bytes(bundle_b):
            raise AssertionError("Charge Gauge signed bundle tree was not byte-for-byte reproducible")
        info = plistlib.loads((bundle_a / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == PLUGIN_ID
        assert info["CFBundleShortVersionString"] == "1.0.0"
        assert info["CFBundleVersion"] == "1"
        exported = run("nm", "-gjU", str(executable_a)).stdout.strip().splitlines()
        assert exported == ["_BattmanPluginEntryPointV1"]
        bundle_strings = run("strings", str(executable_a)).stdout
        if (
            any(value in bundle_strings for value in ("Battman/Features", "Battman/PluginHost"))
            or re.search(r"/Users/[A-Za-z0-9._-]+(?:/|$)", bundle_strings)
        ):
            raise AssertionError("official bundle contains a host-private or checkout path")

        publisher_private, publisher_public, publisher_identifier, publisher_raw = key(
            temporary, "publisher"
        )
        publisher_raw_path = temporary / "publisher.p256"
        publisher_raw_path.write_bytes(publisher_raw)
        manifest = temporary / "Manifest.json"
        run(
            sys.executable, "PluginSDK/Tools/render-example-manifest.py",
            "--template", "OfficialPlugins/ChargeGauge/ManifestTemplate.json.in",
            "--publisher-key-id", publisher_identifier,
            "--output", str(manifest),
        )
        first = temporary / f"{PLUGIN_ID}.first.battman"
        second = temporary / f"{PLUGIN_ID}.second.battman"
        for package in (first, second):
            run(
                sys.executable, "PluginSDK/Tools/Package/build-plugin-package.py",
                "--manifest-template", str(manifest),
                "--payload", str(bundle_a),
                "--publisher-public-key", str(publisher_raw_path),
                "--output", str(package),
            )
        assert (first / "Manifest.json").read_bytes() == (second / "Manifest.json").read_bytes()
        assert (first / "Info.plist").read_bytes() == (second / "Info.plist").read_bytes()
        run(
            sys.executable, "PluginSDK/Tools/Package/sign-plugin-package.py", str(first),
            "--private-key", str(publisher_private),
        )
        verification = json.loads(run(
            sys.executable, "PluginSDK/Tools/Package/verify-plugin-package.py", str(first),
            "--public-key", str(publisher_public),
        ).stdout)
        assert verification["pluginIdentifier"] == PLUGIN_ID
        package_manifest = json.loads((first / "Manifest.json").read_text(encoding="utf-8"))
        assert package_manifest["displayVersion"] == "1.0.0"
        assert package_manifest["buildVersion"] == "1"
        official_wrong_packages = {
            field: signed_package_variant(
                temporary,
                f"official-wrong-{field}",
                manifest,
                bundle_a,
                publisher_private,
                publisher_public,
                publisher_raw_path,
                field,
                value,
            )
            for field, value in (
                ("displayVersion", "1.0.1"),
                ("buildVersion", "2"),
                ("releaseSequence", 2),
            )
        }
        assert package_manifest["author"] == {
            "name": "Torrekie",
            "homepageURL": "https://github.com/Torrekie/Battman",
            "supportEmail": "me@torrekie.dev",
        }
        assert package_manifest["extensionPoints"] == [{
            "identifier": "com.torrekie.battman.analytics.card.v1",
            "interfaceVersion": 1,
        }]
        source = (ROOT / "OfficialPlugins/ChargeGauge/BTChargeGaugePlugin.m").read_text(encoding="utf-8")
        assert CARD_ID in source
        assert "BTChargeGaugeVisualCenterOffset" in source
        assert "colorWithDynamicProvider" in source
        assert "traitCollectionDidChange" in source
        assert "resolvedColorWithTraitCollection" in source
        cell_source = (
            ROOT / "Battman/Features/Analytics/Host/AnalyticsCardCell.m"
        ).read_text(encoding="utf-8")
        assert "UIBlurEffectStyleSystemMaterial" in cell_source
        assert "CGRectInset(self.bounds, -9.0, -9.0)" in cell_source
        assert "constraintEqualToAnchor:_cardView.leadingAnchor constant:3.4" in cell_source
        assert "constraintEqualToConstant:26.0" in cell_source
        assert "[_removeButton convertPoint:point fromView:self]" in cell_source

        rooted = temporary / f"{PLUGIN_ID}_1.0.0_iphoneos-arm.deb"
        rootless = temporary / f"{PLUGIN_ID}_1.0.0_iphoneos-arm64.deb"
        for flavor, output in (("rooted", rooted), ("rootless", rootless)):
            run(
                sys.executable, "Scripts/Release/build-plugin-deb.py",
                "--plugin", str(first), "--flavor", flavor,
                "--version", "1.0.0", "--host-version", "1.1.0",
                "--output", str(output), "--source-date-epoch", EPOCH,
            )
            inspected = inspect_plugin_deb(output, flavor, "1.0.0", PLUGIN_ID, "1.1.0")
            assert inspected["portablePackageVerification"] == "passed"
        havoc_plugin_report = temporary / "havoc-plugin-candidate.json"
        run(
            sys.executable, "Scripts/Release/validate-havoc-candidate.py",
            "--rooted-deb", str(rooted),
            "--rootless-deb", str(rootless),
            "--artifact-kind", "plugin",
            "--version", "1.0.0",
            "--initial-submission",
            "--package", PLUGIN_ID,
            "--host-version", "1.1.0",
            "--section", "Applications",
            "--commit", run("git", "rev-parse", "HEAD").stdout.strip(),
            "--source-tree", run("git", "rev-parse", "HEAD^{tree}").stdout.strip(),
            "--output", str(havoc_plugin_report),
            "--source-date-epoch", EPOCH,
        )
        havoc_plugin = json.loads(havoc_plugin_report.read_text(encoding="utf-8"))
        assert havoc_plugin["status"] == "candidate-only-not-uploaded"
        assert havoc_plugin["candidateEligibility"] == (
            "eligible-for-manual-owner-submission"
        )
        assert havoc_plugin["artifactKind"] == "plugin-debian-pair"
        assert havoc_plugin["publicationState"] == "not-recorded-by-validator"
        assert havoc_plugin["section"] == "Applications"
        assert havoc_plugin["automaticUploadPerformed"] is False

        root_keys = [key(temporary, f"root-{index}") for index in range(1, 4)]
        trust = temporary / "PluginTrust"
        render_arguments = [
            sys.executable, "Scripts/Release/render-official-trust.py",
            *(argument for record in root_keys for argument in ("--root-public-key", str(record[1]))),
            "--publisher-public-key", str(publisher_public),
            "--plugin-identifier", PLUGIN_ID,
            "--extension-point", "com.torrekie.battman.analytics.card.v1",
            "--threshold", "2", "--sequence", "1",
            "--generated-at-unix-seconds", EPOCH,
            "--output", str(trust),
        ]
        run(*render_arguments)
        policy = plistlib.loads((trust / "RootPolicy.plist").read_bytes())
        assert policy["signatureThreshold"] == 2
        assert len(policy["rootPublicKeys"]) == 3
        metadata = json.loads((trust / "TrustMetadata.json").read_text(encoding="utf-8"))
        assert metadata["officialPublishers"][0]["pluginIdentifiers"] == [PLUGIN_ID]
        for private_path, _, _, _ in root_keys[:2]:
            run(
                sys.executable, "Scripts/Release/sign-official-trust.py", str(trust),
                "--private-key", str(private_path),
            )
        trust_report = json.loads(run(
            sys.executable, "Scripts/Release/validate-official-trust.py", str(trust)
        ).stdout)
        assert trust_report["signatureThreshold"] == 2
        assert len(trust_report["verifiedRootKeyIdentifiers"]) == 2
        assert trust_report["officialPublisherKeyIdentifiers"] == [publisher_identifier]

        app = temporary / "Battman.app"
        app.mkdir(mode=0o755)
        executable = app / "Battman"
        sdk_root = run(
            "xcrun", "--sdk", "iphoneos", "--show-sdk-path"
        ).stdout.strip()
        clang = run("xcrun", "--sdk", "iphoneos", "--find", "clang").stdout.strip()
        engineering_identity = temporary / "engineering-BattmanBuildIdentity.json"
        run(
            sys.executable, "Scripts/Build/generate-build-identity.py",
            "--repo", str(ROOT), "--version", "1.1.0",
            "--configuration", "Debug",
            "--product-identifier", "com.torrekie.Battman",
            "--output", str(engineering_identity),
        )
        run(
            clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk_root,
            "-Wl,-no_uuid",
            f"-Wl,-sectcreate,__TEXT,__btidentity,{engineering_identity}",
            "Tests/Release/Fixtures/MinimalAppMain.c",
            "-o", str(executable),
        )
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleExecutable": "Battman",
                "CFBundleIdentifier": "com.torrekie.Battman",
                "CFBundleShortVersionString": "1.1.0",
                "CFBundleVersion": "1.1.0",
                "BTBuildConfiguration": "Debug",
                "GIT_COMMIT_HASH": run("git", "rev-parse", "HEAD").stdout.strip(),
            }, stream, sort_keys=True)
        run(
            "codesign", "--force", "--sign", "-", "--timestamp=none",
            "--identifier", "com.torrekie.Battman", str(app),
        )
        checksum_private, _, checksum_identifier, _ = key(temporary, "checksum")
        example_build = temporary / "sdk-example-build"
        run(
            "make", "-C", "PluginSDK", f"BUILD_DIR={example_build}", "-j1", "example",
        )
        example_private, example_public, example_identifier, example_raw = key(
            temporary, "sdk-example"
        )
        example_raw_path = temporary / "sdk-example.p256"
        example_raw_path.write_bytes(example_raw)
        example_manifest = temporary / "SDKExampleManifest.json"
        run(
            sys.executable, "PluginSDK/Tools/render-example-manifest.py",
            "--publisher-key-id", example_identifier,
            "--output", str(example_manifest),
        )
        sdk_example = temporary / "com.torrekie.battman.example.analytics.battman"
        run(
            sys.executable, "PluginSDK/Tools/Package/build-plugin-package.py",
            "--manifest-template", str(example_manifest),
            "--payload", str(example_build / "BTAnalyticsExample.bundle"),
            "--publisher-public-key", str(example_raw_path),
            "--output", str(sdk_example),
        )
        run(
            sys.executable, "PluginSDK/Tools/Package/sign-plugin-package.py",
            str(sdk_example), "--private-key", str(example_private),
        )
        example_verification = json.loads(run(
            sys.executable, "PluginSDK/Tools/Package/verify-plugin-package.py",
            str(sdk_example), "--public-key", str(example_public),
        ).stdout)
        assert example_verification["pluginIdentifier"] == "com.torrekie.battman.example.analytics"
        sdk_example_wrong_packages = {
            field: signed_package_variant(
                temporary,
                f"sdk-example-wrong-{field}",
                example_manifest,
                example_build / "BTAnalyticsExample.bundle",
                example_private,
                example_public,
                example_raw_path,
                field,
                value,
            )
            for field, value in (
                ("displayVersion", "1.1"),
                ("buildVersion", "2"),
                ("releaseSequence", 2),
            )
        }
        missing_official_release = temporary / "missing-official-release"
        missing_official = subprocess.run(
            [
                sys.executable, "Scripts/Release/assemble-release.py",
                "--repo", str(ROOT),
                "--deb-app", str(app), "--tipa-app", str(app),
                "--version", "1.1.0",
                "--sdk-example", str(sdk_example),
                "--sdk-example-key-id", example_identifier,
                "--checksum-private-key", str(checksum_private),
                "--output-directory", str(missing_official_release),
                "--source-date-epoch", EPOCH,
                "--engineering-candidate",
            ],
            cwd=ROOT,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            capture_output=True,
        )
        assert missing_official.returncode == 2
        assert "official plug-in inputs do not match" in missing_official.stderr
        assert not missing_official_release.exists()
        rejected_release = temporary / "rejected-release"
        rejected = subprocess.run(
            [
                sys.executable, "Scripts/Release/assemble-release.py",
                "--repo", str(ROOT),
                "--deb-app", str(app), "--tipa-app", str(app),
                "--plugin", str(first), "--version", "1.1.0",
                "--sdk-example", str(sdk_example),
                "--sdk-example-key-id", "0" * 64,
                "--checksum-private-key", str(checksum_private),
                "--output-directory", str(rejected_release),
                "--source-date-epoch", EPOCH,
                "--engineering-candidate",
            ],
            cwd=ROOT,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            capture_output=True,
        )
        assert rejected.returncode == 2
        assert "publisher differs from the reviewed fingerprint" in rejected.stderr
        assert not rejected_release.exists()
        release = temporary / "release"
        run(
            sys.executable, "Scripts/Release/assemble-release.py",
            "--repo", str(ROOT),
            "--deb-app", str(app), "--tipa-app", str(app),
            "--plugin", str(first), "--version", "1.1.0",
            "--sdk-example", str(sdk_example),
            "--sdk-example-key-id", example_identifier,
            "--checksum-private-key", str(checksum_private),
            "--output-directory", str(release),
            "--source-date-epoch", EPOCH,
            "--engineering-candidate",
        )
        expected_release_files = {
            f"{PLUGIN_ID}_1.0.0_iphoneos-arm.deb",
            f"{PLUGIN_ID}_1.0.0_iphoneos-arm64.deb",
            f"{PLUGIN_ID}_1.0.0.battman.zip",
            "com.torrekie.battman.example.analytics_1.0.battman.zip",
            "Battman.tipa", "Battman.tipa.report.json",
            "compatibility-matrix.json",
            "artifact-inspection.json", "release-sbom.cdx.json",
            "release-provenance.intoto.jsonl", "release-manifest.json",
            "SHA256SUMS",
        }
        actual_release_files = {path.name for path in release.iterdir()}
        assert expected_release_files <= actual_release_files
        inspection = json.loads((release / "artifact-inspection.json").read_text(encoding="utf-8"))
        kinds = {artifact["kind"] for artifact in inspection["artifacts"]}
        assert {
            "plugin-debian-rooted", "plugin-debian-rootless",
            "plugin-transport", "compatibility-matrix",
            "sdk-example-transport",
        } <= kinds
        transport_record = next(
            artifact for artifact in inspection["artifacts"]
            if artifact["kind"] == "plugin-transport"
        )
        assert transport_record["package"] == PLUGIN_ID
        assert transport_record["archiveRoot"] == f"{PLUGIN_ID}.battman"
        assert {
            key: transport_record[key]
            for key in ("displayVersion", "buildVersion", "releaseSequence")
        } == {
            "displayVersion": "1.0.0",
            "buildVersion": "1",
            "releaseSequence": 1,
        }
        compatibility_record = next(
            artifact for artifact in inspection["artifacts"]
            if artifact["kind"] == "compatibility-matrix"
        )
        assert compatibility_record["fullDeviceMatrixCompleted"] is False
        assert compatibility_record["trollStoreDataDirectoryNativeLoadingClaimed"] is False
        example_record = next(
            artifact for artifact in inspection["artifacts"]
            if artifact["kind"] == "sdk-example-transport"
        )
        assert example_record["package"] == "com.torrekie.battman.example.analytics"
        assert example_record["activationPolicy"] == "third-party-explicit-approval-required"
        assert {
            key: example_record[key]
            for key in ("displayVersion", "buildVersion", "releaseSequence")
        } == {
            "displayVersion": "1.0",
            "buildVersion": "1",
            "releaseSequence": 1,
        }
        tipa_report = json.loads((release / "Battman.tipa.report.json").read_text(encoding="utf-8"))
        assert [record["pluginIdentifier"] for record in tipa_report["embeddedPlugins"]] == [PLUGIN_ID]
        assert "com.torrekie.battman.example.analytics" not in {
            record["pluginIdentifier"] for record in tipa_report["embeddedPlugins"]
        }
        release_manifest = json.loads(
            (release / "release-manifest.json").read_text(encoding="utf-8")
        )
        assert release_manifest["mode"] == "engineering-candidate"
        assert release_manifest["publicationAuthorized"] is False
        assert release_manifest["havocManualSubmission"] == {
            "automaticUpload": False,
            "candidateChannel": "havoc-manual-candidate",
            "classificationReviewRequired": True,
            "dualHostingReviewRequired": True,
            "ownerApprovalRequired": True,
            "publicationState": "not-recorded-by-release-manifest",
        }
        assert "checksumSignatureProcess" not in release_manifest
        assert release_manifest["selectedOfficialPluginIdentifiers"] == [PLUGIN_ID]
        assert release_manifest["signedPluginReleasePins"] == {
            "official": [{
                "pluginIdentifier": PLUGIN_ID,
                "displayVersion": "1.0.0",
                "buildVersion": "1",
                "releaseSequence": 1,
            }],
            "sdkExample": {
                "pluginIdentifier": "com.torrekie.battman.example.analytics",
                "displayVersion": "1.0",
                "buildVersion": "1",
                "releaseSequence": 1,
            },
        }
        assert release_manifest["sdkExampleIdentifier"] == (
            "com.torrekie.battman.example.analytics"
        )
        assert set(release_manifest["expectedFinalAssetNames"]) == actual_release_files
        manifest_records = {
            record["name"]: record for record in release_manifest["artifacts"]
        }
        assert manifest_records[f"{PLUGIN_ID}_1.0.0.battman.zip"] == {
            "activationPolicy": "official-delegation-required",
            "channels": ["github", "direct-import"],
            "kind": "plugin-transport",
            "name": f"{PLUGIN_ID}_1.0.0.battman.zip",
            "package": PLUGIN_ID,
            "sha256": sha256_file(release / f"{PLUGIN_ID}_1.0.0.battman.zip"),
            "size": (release / f"{PLUGIN_ID}_1.0.0.battman.zip").stat().st_size,
        }
        assert manifest_records[f"{PLUGIN_ID}_1.0.0_iphoneos-arm.deb"]["channels"] == [
            "github", "apt-rooted", "havoc-manual-candidate",
        ]
        assert manifest_records[f"{PLUGIN_ID}_1.0.0_iphoneos-arm64.deb"]["channels"] == [
            "github", "apt-rootless", "havoc-manual-candidate",
        ]
        assert manifest_records[f"com.torrekie.battman_1.1.0_iphoneos-arm.deb"][
            "channels"
        ] == ["github", "apt-rooted", "havoc-manual-candidate"]
        assert manifest_records[f"com.torrekie.battman_1.1.0_iphoneos-arm64.deb"][
            "channels"
        ] == ["github", "apt-rootless", "havoc-manual-candidate"]
        assert manifest_records["Battman.tipa"]["channels"] == [
            "github", "trollstore-replacement",
        ]
        for record in manifest_records.values():
            if "havoc-manual-candidate" in record["channels"]:
                assert record["kind"] in {
                    "host-debian-rooted", "host-debian-rootless",
                    "plugin-debian-rooted", "plugin-debian-rootless",
                }
                assert record["name"].endswith(".deb")
        assert manifest_records[
            "com.torrekie.battman.example.analytics_1.0.battman.zip"
        ]["activationPolicy"] == "third-party-explicit-approval-required"
        checksum_names = {
            line.split("  ", 1)[1] for line in
            (release / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
        }
        assert expected_release_files - {"SHA256SUMS"} <= checksum_names
        assert "release-manifest.json" in checksum_names
        sbom = json.loads((release / "release-sbom.cdx.json").read_text(encoding="utf-8"))
        sbom_names = {component["name"] for component in sbom["components"]}
        assert f"{PLUGIN_ID}_1.0.0.battman.zip" in sbom_names
        assert "com.torrekie.battman.example.analytics_1.0.battman.zip" in sbom_names
        assert "compatibility-matrix.json" in sbom_names
        sdk_component = next(
            component for component in sbom["components"]
            if component["name"] == "BattmanPluginSDK-1.1.0.tar.gz"
        )
        assert sdk_component["licenses"] == [{"license": {"id": "MIT"}}]
        assert {
            item["name"]: item["value"] for item in sdk_component["properties"]
        }["battman:licenseFileSHA256"] == (
            "5c85131614b353fb0fae38ca7114bce881baded9382d6718bbe8c2ac30a70edf"
        )
        assert all(
            "licenses" not in component for component in sbom["components"]
            if component is not sdk_component
        )
        provenance = json.loads(
            (release / "release-provenance.intoto.jsonl").read_text(encoding="utf-8")
        )
        provenance_names = {subject["name"] for subject in provenance["subject"]}
        assert f"{PLUGIN_ID}_1.0.0.battman.zip" in provenance_names
        assert "com.torrekie.battman.example.analytics_1.0.battman.zip" in provenance_names
        assert "compatibility-matrix.json" in provenance_names

        verified_directory = json.loads(run(
            sys.executable, "Scripts/Release/verify-release-directory.py", str(release),
        ).stdout)
        assert verified_directory["status"] == "passed"
        assert verified_directory["mode"] == "engineering-candidate"
        unexpected = release / "unreviewed-extra.txt"
        unexpected.write_text("not in the signed release manifest\n", encoding="utf-8")
        rejected_directory = subprocess.run(
            [
                sys.executable, "Scripts/Release/verify-release-directory.py",
                str(release),
            ],
            cwd=ROOT,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            capture_output=True,
        )
        assert rejected_directory.returncode == 2
        assert "exact final asset set" in rejected_directory.stderr
        unexpected.unlink()

        release_manifest_path = release / "release-manifest.json"
        release_manifest_bytes = release_manifest_path.read_bytes()

        def expect_manifest_rejection(tampered, expected_error: str) -> None:
            release_manifest_path.write_text(
                json.dumps(tampered, sort_keys=True, separators=(",", ":")) + "\n",
                encoding="utf-8",
            )
            try:
                rejected = subprocess.run(
                    [
                        sys.executable,
                        "Scripts/Release/verify-release-directory.py",
                        str(release),
                    ],
                    cwd=ROOT,
                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                    text=True,
                    capture_output=True,
                )
                assert rejected.returncode == 2
                assert expected_error in rejected.stderr
            finally:
                release_manifest_path.write_bytes(release_manifest_bytes)

        for policy_mutation in ("missing", "changed", "wrong-type", "extra"):
            tampered = json.loads(release_manifest_bytes)
            policy = tampered["havocManualSubmission"]
            if policy_mutation == "missing":
                policy.pop("ownerApprovalRequired")
            elif policy_mutation == "changed":
                policy["automaticUpload"] = True
            elif policy_mutation == "wrong-type":
                policy["automaticUpload"] = 0
            else:
                policy["unreviewedField"] = False
            expect_manifest_rejection(tampered, "manual-submission policy is malformed")

        rooted_host_name = "com.torrekie.battman_1.1.0_iphoneos-arm.deb"
        tampered = json.loads(release_manifest_bytes)
        rooted_host = next(
            record for record in tampered["artifacts"]
            if record["name"] == rooted_host_name
        )
        rooted_host["channels"].remove("havoc-manual-candidate")
        expect_manifest_rejection(tampered, "does not match artifact eligibility")

        for forbidden_name in (
            "Battman.tipa",
            f"{PLUGIN_ID}_1.0.0.battman.zip",
            "BattmanPluginSDK-1.1.0.tar.gz",
            "release-notes.md",
        ):
            tampered = json.loads(release_manifest_bytes)
            forbidden = next(
                record for record in tampered["artifacts"]
                if record["name"] == forbidden_name
            )
            forbidden["channels"].append("havoc-manual-candidate")
            expect_manifest_rejection(tampered, "does not match artifact eligibility")

        for invalid_channel in ("havoc-rooted", "havoc-unreviewed-channel"):
            tampered = json.loads(release_manifest_bytes)
            rooted_host = next(
                record for record in tampered["artifacts"]
                if record["name"] == rooted_host_name
            )
            rooted_host["channels"].append(invalid_channel)
            expect_manifest_rejection(tampered, "legacy or unknown Havoc channel")

        run(sys.executable, "Scripts/Release/verify-release-directory.py", str(release))

        strict_source = temporary / "strict-source"
        strict_commit = prepare_strict_source(strict_source, first, trust, sdk_example)
        strict_official = (
            strict_source / "OfficialPlugins/Packages" / f"{PLUGIN_ID}.battman"
        )
        strict_example = (
            strict_source / "PluginSDK/Examples/Packages"
            / "com.torrekie.battman.example.analytics.battman"
        )
        strict_app = prepare_strict_app(
            temporary / "strict-app/Battman.app", trust, strict_source
        )
        strict_private, strict_public, strict_checksum_identifier, strict_password = (
            encrypted_key(temporary, "strict-checksum")
        )
        assert strict_source not in strict_private.parents
        assert strict_source not in strict_password.parents

        for role, packages in (
            ("official", official_wrong_packages),
            ("sdk-example", sdk_example_wrong_packages),
        ):
            for field, wrong_package in packages.items():
                wrong_output = temporary / f"strict-wrong-{role}-{field}"
                official_input = wrong_package if role == "official" else strict_official
                example_input = wrong_package if role == "sdk-example" else strict_example
                wrong_result = subprocess.run(
                    [
                        sys.executable,
                        str(strict_source / "Scripts/Release/assemble-release.py"),
                        "--repo", str(strict_source),
                        "--deb-app", str(strict_app), "--tipa-app", str(strict_app),
                        "--plugin", str(official_input),
                        "--sdk-example", str(example_input),
                        "--sdk-example-key-id", example_identifier,
                        "--version", "1.1.0",
                        "--checksum-public-key", str(strict_public),
                        "--checksum-key-id", strict_checksum_identifier,
                        "--output-directory", str(wrong_output),
                        "--source-date-epoch", EPOCH,
                        "--builder-id", "urn:battman:test:strict-release-pin",
                    ],
                    cwd=strict_source,
                    env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                    text=True,
                    capture_output=True,
                )
                assert wrong_result.returncode == 2, (
                    wrong_result.returncode,
                    wrong_result.stderr,
                    wrong_result.stdout,
                )
                label = "signed official plug-in" if role == "official" else "signed SDK example"
                assert f"{label}" in wrong_result.stderr
                assert f"{field} differs from the release pin" in wrong_result.stderr
                assert not wrong_output.exists()

        dirty_marker = strict_source / "strict-release-must-reject-dirty-input.txt"
        dirty_marker.write_text("untracked fixture input\n", encoding="utf-8")
        dirty_output = temporary / "dirty-strict-release"
        dirty_result = subprocess.run(
            [
                sys.executable,
                str(strict_source / "Scripts/Release/assemble-release.py"),
                "--repo", str(strict_source),
                "--deb-app", str(strict_app), "--tipa-app", str(strict_app),
                "--plugin", str(strict_official),
                "--sdk-example", str(strict_example),
                "--sdk-example-key-id", example_identifier,
                "--version", "1.1.0",
                "--checksum-public-key", str(strict_public),
                "--checksum-key-id", strict_checksum_identifier,
                "--output-directory", str(dirty_output),
                "--source-date-epoch", EPOCH,
                "--builder-id", "urn:battman:test:strict-clean-tag",
            ],
            cwd=strict_source,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            capture_output=True,
        )
        assert dirty_result.returncode == 2
        assert "strict release assembly requires a clean checkout" in dirty_result.stderr
        assert not dirty_output.exists()
        dirty_marker.unlink()

        relabeled_app = temporary / "relabeled-app/Battman.app"
        relabeled_app.mkdir(mode=0o755, parents=True)
        run(
            clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk_root,
            "-DBATTMAN_STRICT_HOST_FIXTURE=1", "-Wl,-no_uuid",
            "Tests/Release/Fixtures/MinimalAppMain.c",
            "-o", str(relabeled_app / "Battman"),
        )
        with (relabeled_app / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleExecutable": "Battman",
                "CFBundleIdentifier": "com.torrekie.Battman",
                "CFBundleShortVersionString": "1.1.0",
                "CFBundleVersion": "1.1.0",
                "BTBuildConfiguration": "Release",
                "GIT_COMMIT_HASH": strict_commit,
            }, stream, sort_keys=True)
        shutil.copytree(trust, relabeled_app / "PluginTrust")
        run(
            "codesign", "--force", "--sign", "-", "--timestamp=none",
            "--identifier", "com.torrekie.Battman", str(relabeled_app),
        )
        relabeled_output = temporary / "relabeled-strict-release"
        relabeled_result = subprocess.run(
            [
                sys.executable,
                str(strict_source / "Scripts/Release/assemble-release.py"),
                "--repo", str(strict_source),
                "--deb-app", str(relabeled_app), "--tipa-app", str(relabeled_app),
                "--plugin", str(strict_official),
                "--sdk-example", str(strict_example),
                "--sdk-example-key-id", example_identifier,
                "--version", "1.1.0",
                "--checksum-public-key", str(strict_public),
                "--checksum-key-id", strict_checksum_identifier,
                "--output-directory", str(relabeled_output),
                "--source-date-epoch", EPOCH,
                "--builder-id", "urn:battman:test:strict-clean-tag",
            ],
            cwd=strict_source,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            text=True,
            capture_output=True,
        )
        assert relabeled_result.returncode == 2, (
            relabeled_result.returncode,
            relabeled_result.stderr,
            relabeled_result.stdout,
        )
        assert "host executable has no embedded Battman build identity" in relabeled_result.stderr
        assert not relabeled_output.exists()

        unsigned_candidate = temporary / "strict-unsigned-candidate"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/assemble-release.py"),
            "--repo", str(strict_source),
            "--deb-app", str(strict_app), "--tipa-app", str(strict_app),
            "--plugin", str(strict_official),
            "--sdk-example", str(strict_example),
            "--sdk-example-key-id", example_identifier,
            "--version", "1.1.0",
            "--checksum-public-key", str(strict_public),
            "--checksum-key-id", strict_checksum_identifier,
            "--output-directory", str(unsigned_candidate),
            "--source-date-epoch", EPOCH,
            "--builder-id", "urn:battman:test:strict-clean-tag",
            cwd=strict_source,
        )
        reproduced_candidate = temporary / "strict-unsigned-candidate-reproduced"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/assemble-release.py"),
            "--repo", str(strict_source),
            "--deb-app", str(strict_app), "--tipa-app", str(strict_app),
            "--plugin", str(strict_official),
            "--sdk-example", str(strict_example),
            "--sdk-example-key-id", example_identifier,
            "--version", "1.1.0",
            "--checksum-public-key", str(strict_public),
            "--checksum-key-id", strict_checksum_identifier,
            "--output-directory", str(reproduced_candidate),
            "--source-date-epoch", EPOCH,
            "--builder-id", "urn:battman:test:strict-clean-tag",
            cwd=strict_source,
        )
        assert tree_bytes(unsigned_candidate) == tree_bytes(reproduced_candidate)
        assert not run(
            "git", "status", "--porcelain=v1", "--untracked-files=all",
            cwd=strict_source,
        ).stdout
        unsigned_manifest = json.loads(
            (unsigned_candidate / "release-manifest.json").read_text(encoding="utf-8")
        )
        assert unsigned_manifest["mode"] == "strict-release-candidate"
        assert unsigned_manifest["publicationAuthorized"] is False
        assert unsigned_manifest["checksumSignatureProcess"] == "offline-detached"
        assert unsigned_manifest["commit"] == strict_commit
        assert not (unsigned_candidate / "SHA256SUMS.p256.sig").exists()
        assert (unsigned_candidate / "SHA256SUMS.p256.pub").read_bytes() == (
            strict_public.read_bytes()
        )
        strict_inspection = json.loads(
            (unsigned_candidate / "artifact-inspection.json").read_text(encoding="utf-8")
        )
        strict_sdk = next(
            artifact for artifact in strict_inspection["artifacts"]
            if artifact["kind"] == "plugin-sdk"
        )
        assert strict_sdk["licenseApproved"] is True
        assert strict_sdk["distributionStatus"] == "public-ready"
        assert strict_sdk["licenseIdentifier"] == "MIT"
        assert strict_sdk["licenseSHA256"] == (
            "5c85131614b353fb0fae38ca7114bce881baded9382d6718bbe8c2ac30a70edf"
        )
        strict_hosts = [
            artifact for artifact in strict_inspection["artifacts"]
            if artifact["kind"] in (
                "host-debian-rooted", "host-debian-rootless",
                "trollstore-replacement-tipa",
            )
        ]
        assert len(strict_hosts) == 3
        strict_tipa = next(
            artifact for artifact in strict_hosts
            if artifact["kind"] == "trollstore-replacement-tipa"
        )
        # The replacement TIPA is deliberately unsigned at the outer app
        # boundary and is expected to be signed by its installer.  Strict
        # inspection must therefore work even when the optional `ldid` tool is
        # unavailable on a clean CI runner.
        assert strict_tipa["requiresOuterResign"] is True
        strict_tree = run(
            "git", "rev-parse", "HEAD^{tree}", cwd=strict_source
        ).stdout.strip()
        for host in strict_hosts:
            identity = host["appBuildIdentity"]
            assert identity["configuration"] == "Release"
            assert identity["sourceCommit"] == strict_commit
            assert identity["sourceTree"] == strict_tree
            assert identity["sourceDirty"] is False
        strict_unsigned_verification = json.loads(run(
            sys.executable,
            str(strict_source / "Scripts/Release/verify-release-directory.py"),
            str(unsigned_candidate), "--allow-missing-offline-signature",
            cwd=strict_source,
        ).stdout)
        assert strict_unsigned_verification["status"] == "passed"
        assert strict_unsigned_verification["mode"] == "strict-release-candidate"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/verify-release-directory.py"),
            str(reproduced_candidate), "--allow-missing-offline-signature",
            cwd=strict_source,
        )

        offline_signature = unsigned_candidate / "SHA256SUMS.p256.sig"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/sign-checksums.py"),
            "--private-key", str(strict_private),
            "--checksums", str(unsigned_candidate / "SHA256SUMS"),
            "--signature", str(offline_signature),
            "--password-file", str(strict_password),
            "--source-date-epoch", EPOCH,
            cwd=strict_source,
        )
        returned_signature = temporary / "offline-checksum.sig"
        offline_signature.rename(returned_signature)
        unsigned_verification = json.loads(run(
            sys.executable,
            str(strict_source / "Scripts/Release/verify-release-directory.py"),
            str(unsigned_candidate), "--allow-missing-offline-signature",
            cwd=strict_source,
        ).stdout)
        assert unsigned_verification["status"] == "passed"
        finalized = temporary / "finalized-release"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/finalize-release-signature.py"),
            "--candidate", str(unsigned_candidate),
            "--signature", str(returned_signature),
            "--expected-key-id", strict_checksum_identifier,
            "--output-directory", str(finalized),
            "--source-date-epoch", EPOCH,
            cwd=strict_source,
        )
        final_verification = json.loads(run(
            sys.executable,
            str(strict_source / "Scripts/Release/verify-release-directory.py"),
            str(finalized),
            cwd=strict_source,
        ).stdout)
        assert final_verification["status"] == "passed"
        assert final_verification["mode"] == "strict-release-candidate"
        assert (finalized / "SHA256SUMS.p256.sig").read_bytes() == (
            returned_signature
        ).read_bytes()
        reproduced_finalized = temporary / "finalized-release-reproduced"
        run(
            sys.executable,
            str(strict_source / "Scripts/Release/finalize-release-signature.py"),
            "--candidate", str(reproduced_candidate),
            "--signature", str(returned_signature),
            "--expected-key-id", strict_checksum_identifier,
            "--output-directory", str(reproduced_finalized),
            "--source-date-epoch", EPOCH,
            cwd=strict_source,
        )
        assert tree_bytes(finalized) == tree_bytes(reproduced_finalized)

    print(
        "Official Charge Gauge build, package, Debian, 2-of-3 trust, and "
        "strict clean-tag release tests passed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
