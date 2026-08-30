#!/usr/bin/env python3
"""Build a deterministic public-SDK source archive from the frozen SDK tree."""

from __future__ import annotations

import argparse
import gzip
import os
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath

from release_common import (
    ReleaseError,
    iter_tree,
    require_input_directory,
    require_new_output,
    require_plugin_sdk_license,
    require_version,
    source_date_epoch,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument(
        "--allow-license-pending",
        action="store_true",
        help="build an internal engineering candidate; public distribution remains blocked",
    )
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    version = require_version(arguments.version)
    sdk = require_input_directory(arguments.sdk)
    output = require_new_output(arguments.output, ".gz")
    if not output.name.endswith(".tar.gz"):
        raise ReleaseError("SDK archive output must end in .tar.gz")
    sdk_version = (sdk / "VERSION").read_text(encoding="utf-8").strip()
    if sdk_version != "1":
        raise ReleaseError("SDK ABI/package version is not the frozen v1 contract")
    license_path = sdk / "LICENSE"
    if license_path.exists() or license_path.is_symlink():
        require_plugin_sdk_license(license_path)
    elif not arguments.allow_license_pending:
        raise ReleaseError(
            "PluginSDK/LICENSE is absent; owner license approval is required for public SDK distribution"
        )

    archive_root = f"BattmanPluginSDK-{version}"
    try:
        with output.open("xb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch, compresslevel=9) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    root_info = tarfile.TarInfo(archive_root)
                    root_info.type = tarfile.DIRTYPE
                    root_info.mode = 0o755
                    root_info.mtime = epoch
                    root_info.uid = root_info.gid = 0
                    root_info.uname = root_info.gname = "root"
                    archive.addfile(root_info)
                    for relative, path, entry in iter_tree(sdk):
                        name = f"{archive_root}/{relative}"
                        if PurePosixPath(relative).name == ".DS_Store" or "__pycache__" in PurePosixPath(relative).parts:
                            raise ReleaseError(f"generated file present in SDK source tree: {relative}")
                        info = tarfile.TarInfo(name)
                        info.mtime = epoch
                        info.uid = info.gid = 0
                        info.uname = info.gname = "root"
                        if stat.S_ISDIR(entry.st_mode):
                            info.type = tarfile.DIRTYPE
                            info.mode = 0o755
                            archive.addfile(info)
                        else:
                            info.type = tarfile.REGTYPE
                            info.mode = 0o755 if entry.st_mode & 0o111 else 0o644
                            info.size = entry.st_size
                            with path.open("rb") as stream:
                                archive.addfile(info, stream)
    except Exception:
        if output.is_file() and not output.is_symlink():
            output.unlink()
        raise
    os.utime(output, (epoch, epoch), follow_symlinks=False)
    print(output)
    if not license_path.exists():
        print("warning: internal SDK candidate only; PluginSDK/LICENSE is unresolved", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
