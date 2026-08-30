#!/usr/bin/env python3
"""Build one deterministic rooted or rootless Battman host Debian package."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    copy_tree_normalized,
    load_app_info,
    remove_staged_tree,
    render_template,
    require_identifier,
    require_new_output,
    require_version,
    source_date_epoch,
    temporary_sibling,
    tree_size_kib,
    write_normalized,
)
from debian_archive import build_debian_package


LAYOUTS = {
    "rooted": ("iphoneos-arm", "Applications/Battman.app"),
    "rootless": ("iphoneos-arm64", "var/jb/Applications/Battman.app"),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--flavor", required=True, choices=sorted(LAYOUTS))
    parser.add_argument("--version", required=True)
    parser.add_argument("--package", default="com.torrekie.battman")
    parser.add_argument("--control-template", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--require-release", action="store_true")
    arguments = parser.parse_args()

    epoch = source_date_epoch(arguments.source_date_epoch)
    package_identifier = require_identifier(arguments.package, "Debian package identifier")
    version = require_version(arguments.version)
    output = require_new_output(arguments.output, ".deb")
    info, _ = load_app_info(arguments.app)
    app = arguments.app.resolve()
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != version:
        raise ReleaseError("app bundle versions must exactly match --version")
    if info.get("CFBundleIdentifier") not in ("com.torrekie.Battman", "com.torrekie.Battman.Havoc"):
        raise ReleaseError("unexpected Battman app bundle identifier")
    if arguments.require_release and info.get("BTBuildConfiguration") != "Release":
        raise ReleaseError("release package input is not marked BTBuildConfiguration=Release")
    architecture, install_relative = LAYOUTS[arguments.flavor]
    repo_root = Path(__file__).resolve().parents[2]
    template = (arguments.control_template or repo_root / "Packaging/Debian/Host/control.in").resolve()

    temporary = temporary_sibling(output.parent, ".battman-host-deb-")
    try:
        root = temporary / "root"
        destination = root / install_relative
        copy_tree_normalized(app, destination, epoch)
        installed_size = tree_size_kib(destination)
        control = render_template(template, {
            "PACKAGE": package_identifier,
            "VERSION": version,
            "ARCHITECTURE": architecture,
            "INSTALLED_SIZE": str(installed_size),
        })
        write_normalized(root / "DEBIAN/control", control.encode("utf-8"), epoch)
        candidate = temporary / output.name
        build_debian_package(root, candidate, epoch, temporary)
        os.replace(candidate, output)
        os.utime(output, (epoch, epoch), follow_symlinks=False)
    finally:
        if temporary.exists():
            remove_staged_tree(temporary, output.parent)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
