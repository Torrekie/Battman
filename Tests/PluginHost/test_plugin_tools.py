#!/usr/bin/env python3
"""Exercise deterministic package construction and portable offline verification."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


def run(*arguments: str, expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(arguments, text=True, capture_output=True, env=environment, check=False)
    if (result.returncode == 0) != expect_success:
        stream = result.stderr if expect_success else result.stdout
        raise AssertionError(f"unexpected command status {result.returncode}: {' '.join(arguments)}\n{stream}")
    return result


def schema_length_accepts(definition: dict[str, object], value: str) -> bool:
    """Evaluate JSON Schema string-length bounds in Unicode code points."""
    minimum_length = definition.get("minLength")
    maximum_length = definition.get("maxLength")
    assert isinstance(minimum_length, int)
    assert isinstance(maximum_length, int)
    return minimum_length <= len(value) <= maximum_length


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: test_plugin_tools.py VALID_BUNDLE VALID_SO REPOSITORY_ROOT")
    fixture_executable = Path(sys.argv[1]).resolve()
    fixture_so = Path(sys.argv[2]).resolve()
    repository_root = Path(sys.argv[3]).resolve()
    tools = repository_root / "PluginSDK" / "Tools" / "Package"
    schema_paths = [
        repository_root / "PluginSDK" / "schema" / "BattmanPluginManifestV1.schema.json",
        repository_root / "PluginSDK" / "schema" / "BattmanPluginTrustMetadataV1.schema.json",
    ]
    manifest_schema = None
    for schema_path in schema_paths:
        parsed = json.loads(schema_path.read_text(encoding="utf-8"))
        assert parsed["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        if schema_path.name == "BattmanPluginManifestV1.schema.json":
            manifest_schema = parsed
    assert isinstance(manifest_schema, dict)

    with tempfile.TemporaryDirectory(prefix="battman-plugin-tools-tests-") as directory:
        root = Path(directory)
        payload = root / "Example.bundle"
        payload.mkdir(mode=0o755)
        shutil.copy2(fixture_executable, payload / "Example")
        os.chmod(payload / "Example", 0o755)
        with (payload / "Info.plist").open("wb") as stream:
            plistlib.dump(
                {
                    "CFBundleExecutable": "Example",
                    "CFBundleIdentifier": "com.example.battman.tools",
                    "CFBundlePackageType": "BNDL",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                },
                stream,
                fmt=plistlib.FMT_BINARY,
                sort_keys=True,
            )
        os.chmod(payload / "Info.plist", 0o644)

        so_payload = root / "Example.so"
        shutil.copy2(fixture_so, so_payload)
        os.chmod(so_payload, 0o755)

        private_key = ec.generate_private_key(ec.SECP256R1())
        public_key = private_key.public_key()
        raw_public_key = public_key.public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
        )
        digest = hashes.Hash(hashes.SHA256())
        digest.update(raw_public_key)
        key_identifier = digest.finalize().hex()
        private_path = root / "ephemeral-test-private.pem"
        public_path = root / "ephemeral-test-public.pem"
        private_path.write_bytes(
            private_key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        )
        public_path.write_bytes(
            public_key.public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            )
        )
        os.chmod(private_path, 0o600)

        template = {
            "formatVersion": 1,
            "schemaVersion": 1,
            "pluginIdentifier": "com.example.battman.tools",
            "displayName": "Tool Fixture",
            "displayVersion": "1.0",
            "buildVersion": "1",
            "publisher": {
                "primaryKeyIdentifier": key_identifier,
                "signatureKeyIdentifiers": [key_identifier],
                "algorithm": "ecdsa-p256-sha256",
            },
            "author": {
                "name": "Tool Fixture Developer",
                "homepageURL": "https://example.com/battman-tools",
                "supportEmail": "support@example.com",
            },
            "hostABI": {"minimum": 1, "maximum": 1},
            "payload": {
                "path": "Example.bundle",
                "kind": "bundle",
                "executablePath": "Example.bundle/Example",
                "architecture": "arm64",
                "minimumIOSVersion": "12.0",
                "entryPoint": "BattmanPluginEntryPointV1",
            },
            "extensionPoints": [
                {
                    "identifier": "com.torrekie.battman.analytics.card.v1",
                    "interfaceVersion": 1,
                }
            ],
            "dependencies": [],
            "releaseSequence": 1,
        }
        template_path = root / "ManifestTemplate.json"
        template_path.write_text(json.dumps(template, sort_keys=True), encoding="utf-8")
        first = root / "First.battman"
        second = root / "Second.battman"
        build_tool = str(tools / "build-plugin-package.py")

        astral_character = "\U0001f680"
        display_name_at_limit = astral_character * 256
        display_name_over_limit = astral_character * 257
        author_name_at_limit = astral_character * 128
        author_name_over_limit = astral_character * 129
        assert manifest_schema["properties"]["displayName"]["$ref"] == "#/$defs/displayString"
        assert manifest_schema["properties"]["author"]["$ref"] == "#/$defs/author"
        display_string_schema = manifest_schema["$defs"]["displayString"]
        author_name_schema = manifest_schema["$defs"]["author"]["properties"]["name"]
        assert schema_length_accepts(display_string_schema, display_name_at_limit)
        assert not schema_length_accepts(display_string_schema, display_name_over_limit)
        assert schema_length_accepts(author_name_schema, author_name_at_limit)
        assert not schema_length_accepts(author_name_schema, author_name_over_limit)

        astral_boundary_template = json.loads(json.dumps(template))
        astral_boundary_template["displayName"] = display_name_at_limit
        astral_boundary_template["author"]["name"] = author_name_at_limit
        astral_boundary_path = root / "AstralBoundaryManifest.json"
        astral_boundary_path.write_text(
            json.dumps(astral_boundary_template, sort_keys=True), encoding="utf-8"
        )
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(astral_boundary_path),
            "--payload",
            str(payload),
            "--output",
            str(root / "AstralBoundary.battman"),
        )

        display_name_over_limit_template = json.loads(json.dumps(astral_boundary_template))
        display_name_over_limit_template["displayName"] = display_name_over_limit
        author_name_over_limit_template = json.loads(json.dumps(astral_boundary_template))
        author_name_over_limit_template["author"]["name"] = author_name_over_limit
        for label, over_limit_template in (
            ("DisplayName", display_name_over_limit_template),
            ("AuthorName", author_name_over_limit_template),
        ):
            over_limit_path = root / f"Astral{label}OverLimitManifest.json"
            over_limit_path.write_text(
                json.dumps(over_limit_template, sort_keys=True), encoding="utf-8"
            )
            run(
                sys.executable,
                build_tool,
                "--manifest-template",
                str(over_limit_path),
                "--payload",
                str(payload),
                "--output",
                str(root / f"Astral{label}OverLimit.battman"),
                expect_success=False,
            )

        for index, invalid_display_name in enumerate(
            (
                " Leading Space",
                "Trailing Space ",
                "Injected\nWarning",
                "Injected\u2028Warning",
                "Injected\u2029Warning",
                "Reordered \u202eName",
                "Cafe\u0301",
            )
        ):
            invalid_template = json.loads(json.dumps(template))
            invalid_template["displayName"] = invalid_display_name
            invalid_template_path = root / f"InvalidDisplayName{index}.json"
            invalid_template_path.write_text(
                json.dumps(invalid_template, sort_keys=True), encoding="utf-8"
            )
            run(
                sys.executable,
                build_tool,
                "--manifest-template",
                str(invalid_template_path),
                "--payload",
                str(payload),
                "--output",
                str(root / f"InvalidDisplayName{index}.battman"),
                expect_success=False,
            )

        for output in (first, second):
            run(
                sys.executable,
                build_tool,
                "--manifest-template",
                str(template_path),
                "--payload",
                str(payload),
                "--output",
                str(output),
            )

        invalid_bundle_info_values = (
            ("CFBundleExecutable", "Wrong"),
            ("CFBundleIdentifier", "com.example.wrong"),
            ("CFBundlePackageType", "APPL"),
            ("CFBundleShortVersionString", "2.0"),
            ("CFBundleVersion", "2"),
        )
        for index, (key, value) in enumerate(invalid_bundle_info_values):
            invalid_payload = root / f"InvalidBundleInfo{index}.bundle"
            shutil.copytree(payload, invalid_payload)
            invalid_info_path = invalid_payload / "Info.plist"
            invalid_info = plistlib.loads(invalid_info_path.read_bytes())
            invalid_info[key] = value
            invalid_info_path.write_bytes(
                plistlib.dumps(invalid_info, fmt=plistlib.FMT_BINARY, sort_keys=True)
            )
            run(
                sys.executable,
                build_tool,
                "--manifest-template",
                str(template_path),
                "--payload",
                str(invalid_payload),
                "--output",
                str(root / f"InvalidBundleInfo{index}.battman"),
                expect_success=False,
            )

        missing_info_payload = root / "MissingBundleInfo.bundle"
        shutil.copytree(payload, missing_info_payload)
        (missing_info_payload / "Info.plist").unlink()
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(template_path),
            "--payload",
            str(missing_info_payload),
            "--output",
            str(root / "MissingBundleInfo.battman"),
            expect_success=False,
        )
        assert (first / "Manifest.json").read_bytes() == (second / "Manifest.json").read_bytes()
        assert (first / "Info.plist").read_bytes() == (second / "Info.plist").read_bytes()
        assert json.loads((first / "Manifest.json").read_text(encoding="utf-8"))["author"] == template["author"]

        so_template = json.loads(json.dumps(template))
        so_template["payload"] = {
            "path": "Example.so",
            "kind": "so",
            "executablePath": "Example.so",
            "architecture": "arm64",
            "minimumIOSVersion": "12.0",
            "entryPoint": "BattmanPluginEntryPointV1",
        }
        so_template_path = root / "SOManifestTemplate.json"
        so_template_path.write_text(json.dumps(so_template, sort_keys=True), encoding="utf-8")
        so_package = root / "RawSO.battman"
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(so_template_path),
            "--payload",
            str(so_payload),
            "--output",
            str(so_package),
        )
        built_so_manifest = json.loads((so_package / "Manifest.json").read_text(encoding="utf-8"))
        built_so_payload = dict(built_so_manifest["payload"])
        code_identity = built_so_payload.pop("codeIdentity")
        assert built_so_payload == so_template["payload"]
        assert code_identity["algorithm"] == "macho-codesign-independent-sha256-v1"
        assert code_identity["unsignedByteCount"] > 0
        assert len(code_identity["sha256"]) == 64
        assert built_so_manifest["files"][0]["path"] == "Example.so"
        assert built_so_manifest["files"][0]["mode"] == "executable"

        linked_payload = root / "LinkedPayload.bundle"
        linked_payload.mkdir(mode=0o755)
        os.symlink(payload / "Example", linked_payload / "Example")
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(template_path),
            "--payload",
            str(linked_payload),
            "--output",
            str(root / "LinkedPayload.battman"),
            expect_success=False,
        )

        escaping_template = dict(template)
        escaping_template["payload"] = dict(template["payload"])
        escaping_template["payload"]["path"] = "../Escaped.bundle"
        escaping_path = root / "EscapingManifest.json"
        escaping_path.write_text(json.dumps(escaping_template, sort_keys=True), encoding="utf-8")
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(escaping_path),
            "--payload",
            str(payload),
            "--output",
            str(root / "Escaping.battman"),
            expect_success=False,
        )
        assert not (root / "Escaped.bundle").exists()

        invalid_author_template = dict(template)
        invalid_author_template["author"] = {
            "name": "Impersonator\u202e",
            "homepageURL": "https://user@example.com",
            "supportEmail": "support@localhost",
        }
        invalid_author_path = root / "InvalidAuthorManifest.json"
        invalid_author_path.write_text(
            json.dumps(invalid_author_template, sort_keys=True), encoding="utf-8"
        )
        run(
            sys.executable,
            build_tool,
            "--manifest-template",
            str(invalid_author_path),
            "--payload",
            str(payload),
            "--output",
            str(root / "InvalidAuthor.battman"),
            expect_success=False,
        )

        signer = str(tools / "sign-plugin-package.py")
        signed_identifier = run(
            sys.executable, signer, str(first), "--private-key", str(private_path)
        ).stdout.strip()
        assert signed_identifier == key_identifier
        original_signature = (first / "Signatures" / f"{key_identifier}.sig").read_bytes()
        run(
            sys.executable,
            signer,
            str(first),
            "--private-key",
            str(private_path),
            expect_success=False,
        )
        assert (first / "Signatures" / f"{key_identifier}.sig").read_bytes() == original_signature
        verifier = str(tools / "verify-plugin-package.py")

        portable_invalid = root / "PortableInvalidBundleInfo.battman"
        shutil.copytree(second, portable_invalid)
        portable_info_path = portable_invalid / "Example.bundle" / "Info.plist"
        portable_info = plistlib.loads(portable_info_path.read_bytes())
        portable_info["CFBundleIdentifier"] = "com.example.wrong"
        portable_info_data = plistlib.dumps(portable_info, fmt=plistlib.FMT_BINARY, sort_keys=True)
        portable_info_path.write_bytes(portable_info_data)
        portable_manifest_path = portable_invalid / "Manifest.json"
        portable_manifest = json.loads(portable_manifest_path.read_text(encoding="utf-8"))
        portable_record = next(
            entry
            for entry in portable_manifest["files"]
            if entry["path"] == "Example.bundle/Info.plist"
        )
        portable_record["size"] = len(portable_info_data)
        portable_record["sha256"] = hashlib.sha256(portable_info_data).hexdigest()
        portable_manifest_path.write_text(
            json.dumps(portable_manifest, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        run(
            sys.executable, signer, str(portable_invalid), "--private-key", str(private_path)
        )
        run(
            sys.executable,
            verifier,
            str(portable_invalid),
            "--public-key",
            str(public_path),
            expect_success=False,
        )

        for index, invalid_format_version in enumerate((1.0, True)):
            portable_format = root / f"PortableInvalidFormat{index}.battman"
            shutil.copytree(second, portable_format)
            outer_info_path = portable_format / "Info.plist"
            outer_info = plistlib.loads(outer_info_path.read_bytes())
            outer_info["BTPluginPackageFormatVersion"] = invalid_format_version
            outer_info_data = plistlib.dumps(outer_info, fmt=plistlib.FMT_BINARY, sort_keys=True)
            outer_info_path.write_bytes(outer_info_data)
            format_manifest_path = portable_format / "Manifest.json"
            format_manifest = json.loads(format_manifest_path.read_text(encoding="utf-8"))
            format_record = next(
                entry for entry in format_manifest["files"] if entry["path"] == "Info.plist"
            )
            format_record["size"] = len(outer_info_data)
            format_record["sha256"] = hashlib.sha256(outer_info_data).hexdigest()
            format_manifest_path.write_text(
                json.dumps(format_manifest, sort_keys=True, separators=(",", ":")) + "\n",
                encoding="utf-8",
            )
            run(
                sys.executable, signer, str(portable_format), "--private-key", str(private_path)
            )
            run(
                sys.executable,
                verifier,
                str(portable_format),
                "--public-key",
                str(public_path),
                expect_success=False,
            )

        result = run(
            sys.executable, verifier, str(first), "--public-key", str(public_path)
        )
        report = json.loads(result.stdout)
        assert report["pluginIdentifier"] == template["pluginIdentifier"]
        assert report["nativeVerificationRequired"] is True
        assert report["verifiedPublisherKeys"] == [f"{key_identifier}:external"]

        so_signed_identifier = run(
            sys.executable, signer, str(so_package), "--private-key", str(private_path)
        ).stdout.strip()
        assert so_signed_identifier == key_identifier
        so_result = run(
            sys.executable, verifier, str(so_package), "--public-key", str(public_path)
        )
        so_report = json.loads(so_result.stdout)
        assert so_report["pluginIdentifier"] == so_template["pluginIdentifier"]
        assert so_report["nativeVerificationRequired"] is True
        assert so_report["verifiedPublisherKeys"] == [f"{key_identifier}:external"]
        assert {
            path.relative_to(so_package).as_posix()
            for path in so_package.rglob("*")
            if path.is_file()
        } == {
            "Example.so",
            "Info.plist",
            "Manifest.json",
            f"Signatures/{key_identifier}.sig",
        }

        package_link = root / "FirstLink.battman"
        package_link.symlink_to(first, target_is_directory=True)
        run(
            sys.executable,
            verifier,
            str(package_link),
            "--public-key",
            str(public_path),
            expect_success=False,
        )

        tampered = root / "Tampered.battman"
        shutil.copytree(first, tampered)
        (tampered / "unexpected.txt").write_text("not signed", encoding="utf-8")
        run(
            sys.executable,
            verifier,
            str(tampered),
            "--public-key",
            str(public_path),
            expect_success=False,
        )

    print("Deterministic bundle/.so package-tool and portable offline verification tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
