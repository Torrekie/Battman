#!/usr/bin/env python3
"""Archive the buildable Analytics examples, public SDK, and their licenses."""
from __future__ import annotations

import argparse
import gzip
import os
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath

from release_common import (ReleaseError, iter_tree, require_input_directory,
                            require_new_output, require_plugin_sdk_license,
                            require_version, source_date_epoch)
from source_archive import require_source_path

SOURCE_ROOTS = ("PluginSDK", "OfficialPlugins/ChargeGauge", "LICENSE")
REQUIRED = (
    "PluginSDK/LICENSE", "PluginSDK/include/BattmanPluginABI.h", "PluginSDK/Makefile",
    "PluginSDK/Examples/AnalyticsCard/BTAnalyticsExamplePlugin.m",
    "OfficialPlugins/ChargeGauge/Makefile", "OfficialPlugins/ChargeGauge/BTChargeGaugePlugin.m",
    "OfficialPlugins/ChargeGauge/Info.plist", "OfficialPlugins/ChargeGauge/ManifestTemplate.json.in",
    "OfficialPlugins/ChargeGauge/Resources/en.lproj/Localizable.strings",
    "LICENSE/LICENSE.md", "LICENSE/LICENSE-en_US.md",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    args = parser.parse_args()
    repo = require_input_directory(args.repo)
    version = require_version(args.version)
    epoch = source_date_epoch(args.source_date_epoch)
    output = require_new_output(args.output, ".gz")
    if not output.name.endswith(".tar.gz"):
        raise ReleaseError("example source archive output must end in .tar.gz")
    require_plugin_sdk_license(repo / "PluginSDK/LICENSE")
    entries = []
    for source_root in SOURCE_ROOTS:
        directory = require_input_directory(repo / source_root)
        entries.append((source_root, directory, directory.stat()))
        for relative, path, entry in iter_tree(directory):
            if source_root == "PluginSDK" and PurePosixPath(relative).parts[:2] == ("Examples", "Packages"):
                continue
            require_source_path(relative)
            entries.append((f"{source_root}/{relative}", path, entry))
    names = {relative for relative, _, _ in entries}
    if not set(REQUIRED) <= names:
        raise ReleaseError("example source archive is missing build inputs or licenses")
    prefix = f"BattmanPluginExamples-{version}"
    try:
        with output.open("xb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch, compresslevel=9) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    for relative, path, entry in sorted(entries, key=lambda item: item[0].encode("utf-8")):
                        info = tarfile.TarInfo(f"{prefix}/{relative}")
                        info.mtime = epoch
                        info.uid = info.gid = 0
                        info.uname = info.gname = "root"
                        if stat.S_ISDIR(entry.st_mode):
                            info.type = tarfile.DIRTYPE
                            info.mode = 0o755
                            archive.addfile(info)
                        else:
                            info.mode = 0o755 if entry.st_mode & 0o111 else 0o644
                            info.size = entry.st_size
                            with path.open("rb") as stream:
                                archive.addfile(info, stream)
    except Exception:
        output.unlink(missing_ok=True)
        raise
    os.utime(output, (epoch, epoch), follow_symlinks=False)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
