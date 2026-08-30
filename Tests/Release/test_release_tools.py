#!/usr/bin/env python3
"""Adversarial unit tests for bounded release primitives."""

from __future__ import annotations

import io
import json
import lzma
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/Release"))

from debian_archive import (  # noqa: E402
    build_debian_package,
    data_members,
    extract_data,
    read_ar_members,
)
from release_common import (  # noqa: E402
    ReleaseError,
    deterministic_zip,
    iter_tree,
    require_package_version,
    require_plugin_sdk_license,
    require_version,
)
from release_inputs import require_tracked_public_input  # noqa: E402
from host_build_identity import (  # noqa: E402
    canonical_identity_bytes,
    extract_embedded_identity,
    parse_identity_bytes,
    require_embedded_identity,
)


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (OSError, ReleaseError, tarfile.TarError, lzma.LZMAError):
        return
    raise AssertionError(f"expected hard failure: {label}")


def ar_member(name: str, data: bytes) -> bytes:
    header = (
        f"{name}/".ljust(16)
        + "1700000000".ljust(12)
        + "0".ljust(6)
        + "0".ljust(6)
        + "100644".ljust(8)
        + str(len(data)).ljust(10)
        + "`\n"
    ).encode("ascii")
    return header + data + (b"\n" if len(data) & 1 else b"")


def hostile_deb(path: Path, hostile_name: str, *, symlink: bool = False) -> None:
    control_buffer = io.BytesIO()
    with tarfile.open(fileobj=control_buffer, mode="w") as archive:
        root = tarfile.TarInfo("./")
        root.type = tarfile.DIRTYPE
        root.mode = 0o755
        archive.addfile(root)
        payload = b"Package: com.example.fixture\nVersion: 1\nArchitecture: iphoneos-arm\n"
        control = tarfile.TarInfo("./control")
        control.mode = 0o644
        control.size = len(payload)
        archive.addfile(control, io.BytesIO(payload))
    data_buffer = io.BytesIO()
    with tarfile.open(fileobj=data_buffer, mode="w") as archive:
        member = tarfile.TarInfo(hostile_name)
        member.mode = 0o755 if symlink else 0o644
        if symlink:
            member.type = tarfile.SYMTYPE
            member.linkname = "/etc/passwd"
            archive.addfile(member)
        else:
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
    parts = [
        ar_member("debian-binary", b"2.0\n"),
        ar_member("control.tar.xz", lzma.compress(control_buffer.getvalue())),
        ar_member("data.tar.xz", lzma.compress(data_buffer.getvalue())),
    ]
    path.write_bytes(b"!<arch>\n" + b"".join(parts))


def tar_type_flags(data: bytes) -> list[bytes]:
    flags: list[bytes] = []
    offset = 0
    while offset + 512 <= len(data):
        header = data[offset:offset + 512]
        if header == b"\0" * 512:
            break
        size_field = header[124:136].rstrip(b"\0 ") or b"0"
        size = int(size_field, 8)
        flags.append(header[156:157])
        offset += 512 + ((size + 511) // 512) * 512
    return flags


def main() -> int:
    for value in ("1.1.0", "1.0.3.3", "0.1.0", "10.20.30.40"):
        assert require_version(value) == value
    for value in ("1.1", "1.1.0.0.1", "1.1.0-alpha", "v1.1.0", "01.1.0"):
        expect_failure(lambda value=value: require_version(value), f"invalid Battman version {value}")
    for value in ("1", "1.0", "1.0.0", "1.0.0.1"):
        assert require_package_version(value) == value
    for value in ("", "01", "1-alpha", "1.0.0.0.1"):
        expect_failure(
            lambda value=value: require_package_version(value),
            f"invalid plug-in package version {value}",
        )

    with tempfile.TemporaryDirectory(prefix="battman-release-unit-") as raw:
        temporary = Path(raw)
        require_plugin_sdk_license(ROOT / "PluginSDK/LICENSE")
        wrong_license = temporary / "LICENSE"
        wrong_license.write_text("MIT\n", encoding="utf-8")
        expect_failure(
            lambda: require_plugin_sdk_license(wrong_license),
            "noncanonical PluginSDK license",
        )
        source = temporary / "tree"
        source.mkdir(mode=0o755)
        (source / "data").write_text("hello", encoding="utf-8")
        executable = source / "run"
        executable.write_text("fixture", encoding="utf-8")
        executable.chmod(0o755)
        first = temporary / "first.zip"
        second = temporary / "second.zip"
        deterministic_zip(source, first, 1700000000)
        deterministic_zip(source, second, 1700000000)
        assert first.read_bytes() == second.read_bytes()
        with zipfile.ZipFile(first) as archive:
            modes = {info.filename: (info.external_attr >> 16) & 0o777 for info in archive.infolist()}
            assert modes == {"data": 0o644, "run": 0o755}

        link = source / "link"
        link.symlink_to("data")
        expect_failure(lambda: list(iter_tree(source)), "release input symlink")
        link.unlink()
        os.link(source / "data", source / "hard")
        expect_failure(lambda: list(iter_tree(source)), "release input hard link")

        directory = temporary / "real-directory"
        directory.mkdir(mode=0o755)
        directory_link = temporary / "directory-link"
        directory_link.symlink_to(directory, target_is_directory=True)
        from release_common import require_input_directory, require_new_output
        expect_failure(lambda: require_input_directory(directory_link), "top-level input symlink")
        parent_link = temporary / "parent-link"
        parent_link.symlink_to(directory, target_is_directory=True)
        expect_failure(lambda: require_new_output(parent_link / "output.zip"), "output parent symlink")

        traversal = temporary / "traversal.deb"
        hostile_deb(traversal, "../../escape")
        members = read_ar_members(traversal)
        expect_failure(lambda: data_members(members), "Debian traversal member")
        destination = temporary / "extracted"
        expect_failure(lambda: extract_data(members, destination), "Debian traversal extraction")
        assert not (temporary / "escape").exists()

        link_deb = temporary / "link.deb"
        hostile_deb(link_deb, "./Applications/link", symlink=True)
        expect_failure(lambda: data_members(read_ar_members(link_deb)), "Debian symlink member")

        compatible_root = temporary / "compatible-deb-root"
        (compatible_root / "DEBIAN").mkdir(mode=0o755, parents=True)
        (compatible_root / "DEBIAN/control").write_text(
            "Package: com.example.fixture\nVersion: 1\nArchitecture: iphoneos-arm64\n",
            encoding="utf-8",
        )
        long_payload = (
            compatible_root / "var/jb/Library/Battman/PlugIns"
            / "com.torrekie.battman.plugin.charge-gauge.battman/PublisherKeys"
            / ("0" * 64 + ".p256")
        )
        long_payload.parent.mkdir(mode=0o755, parents=True)
        long_payload.write_bytes(b"engineering fixture\n")
        compatible_work = temporary / "compatible-deb-work"
        compatible_work.mkdir(mode=0o700)
        compatible_deb = temporary / "compatible.deb"
        build_debian_package(compatible_root, compatible_deb, 1700000000, compatible_work)
        compatible_members = read_ar_members(compatible_deb)
        for member_name in ("control.tar.xz", "data.tar.xz"):
            flags = tar_type_flags(lzma.decompress(compatible_members[member_name]))
            assert flags and set(flags) <= {b"0", b"5"}
            assert b"x" not in flags and b"g" not in flags
        assert data_members(compatible_members)

        duplicate = temporary / "duplicate.deb"
        original = traversal.read_bytes()
        duplicate.write_bytes(original + ar_member("data.tar.xz", b"x"))
        expect_failure(lambda: read_ar_members(duplicate), "duplicate Debian member")

        repository = temporary / "release-input-repository"
        repository.mkdir(mode=0o755)
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        subprocess.run(
            ["git", "-C", str(repository), "config", "user.email", "release-test@example.invalid"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(repository), "config", "user.name", "Battman Release Test"],
            check=True,
        )
        public_input = repository / "PublicInput"
        public_input.mkdir(mode=0o755)
        (public_input / "tracked.json").write_text("{}\n", encoding="utf-8")
        subprocess.run(
            ["git", "-C", str(repository), "add", "PublicInput/tracked.json"], check=True,
        )
        subprocess.run(
            ["git", "-C", str(repository), "commit", "-qm", "tracked public fixture"],
            check=True,
        )
        require_tracked_public_input(repository, public_input, "public fixture")
        (public_input / "injected.json").write_text("{}\n", encoding="utf-8")
        expect_failure(
            lambda: require_tracked_public_input(repository, public_input, "public fixture"),
            "untracked public release input",
        )
        outside_public = temporary / "outside-public"
        outside_public.mkdir(mode=0o755)
        (outside_public / "public.json").write_text("{}\n", encoding="utf-8")
        expect_failure(
            lambda: require_tracked_public_input(repository, outside_public, "public fixture"),
            "public release input outside checkout",
        )
        encrypted_private = temporary / "encrypted-checksum-private.pem"
        encrypted_password = temporary / "encrypted-checksum-password"
        encrypted_password.write_bytes(b"test-only-password\n")
        encrypted_private.write_bytes(ec.generate_private_key(
            ec.SECP256R1()
        ).private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.BestAvailableEncryption(b"test-only-password"),
        ))
        checksums = temporary / "SHA256SUMS"
        checksums.write_text("0" * 64 + "  fixture\n", encoding="utf-8")
        signature = temporary / "SHA256SUMS.p256.sig"
        subprocess.run([
            sys.executable,
            str(ROOT / "Scripts/Release/sign-checksums.py"),
            "--private-key", str(encrypted_private),
            "--password-file", str(encrypted_password),
            "--checksums", str(checksums),
            "--signature", str(signature),
            "--source-date-epoch", "1700000000",
        ], check=True, stdout=subprocess.DEVNULL)
        assert signature.is_file() and 1 <= signature.stat().st_size <= 256

        identity = {
            "configuration": "Release",
            "productIdentifier": "com.torrekie.Battman",
            "schemaVersion": 1,
            "sourceCommit": "1" * 40,
            "sourceDirty": False,
            "sourceTree": "2" * 40,
            "version": "1.1.0",
        }
        identity_file = temporary / "BattmanBuildIdentity.json"
        identity_file.write_bytes(canonical_identity_bytes(identity))
        sdk_root = subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"],
            check=True, text=True, capture_output=True,
        ).stdout.strip()
        clang = subprocess.run(
            ["xcrun", "--sdk", "iphoneos", "--find", "clang"],
            check=True, text=True, capture_output=True,
        ).stdout.strip()
        identified_macho = temporary / "identified-host"
        subprocess.run([
            clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk_root,
            "-Wl,-no_uuid",
            f"-Wl,-sectcreate,__TEXT,__btidentity,{identity_file}",
            str(ROOT / "Tests/Release/Fixtures/MinimalAppMain.c"),
            "-o", str(identified_macho),
        ], check=True, stdout=subprocess.DEVNULL)
        assert extract_embedded_identity(identified_macho) == identity
        assert require_embedded_identity(
            identified_macho,
            version="1.1.0",
            configuration="Release",
            product_identifier="com.torrekie.Battman",
            source_commit="1" * 40,
            source_tree="2" * 40,
            source_dirty=False,
        ) == identity
        expect_failure(
            lambda: require_embedded_identity(
                identified_macho,
                version="1.1.0",
                configuration="Release",
                product_identifier="com.torrekie.Battman",
                source_commit="3" * 40,
            ),
            "mismatched embedded source commit",
        )
        unidentified_macho = temporary / "unidentified-host"
        subprocess.run([
            clang, "-target", "arm64-apple-ios12.0", "-isysroot", sdk_root,
            "-Wl,-no_uuid", str(ROOT / "Tests/Release/Fixtures/MinimalAppMain.c"),
            "-o", str(unidentified_macho),
        ], check=True, stdout=subprocess.DEVNULL)
        expect_failure(
            lambda: extract_embedded_identity(unidentified_macho),
            "missing embedded host identity",
        )
        noncanonical = json.dumps(identity, indent=2, sort_keys=True).encode("ascii")
        expect_failure(
            lambda: parse_identity_bytes(noncanonical),
            "noncanonical embedded identity JSON",
        )

    print("Release archive, boundary, and embedded build-identity tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
