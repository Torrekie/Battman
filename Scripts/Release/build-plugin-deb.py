#!/usr/bin/env python3
"""Build one deterministic rooted or rootless signed .battman Debian package."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    copy_tree_normalized,
    render_template,
    remove_staged_tree,
    require_identifier,
    require_input_directory,
    require_new_output,
    require_package_version,
    require_version,
    run,
    source_date_epoch,
    temporary_sibling,
    tree_size_kib,
    write_normalized,
)
from debian_archive import build_debian_package


LAYOUTS = {
    "rooted": ("iphoneos-arm", "Library/Battman/PlugIns"),
    "rootless": ("iphoneos-arm64", "var/jb/Library/Battman/PlugIns"),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin", required=True, type=Path)
    parser.add_argument("--flavor", required=True, choices=sorted(LAYOUTS))
    parser.add_argument("--version", required=True, help="Debian package version")
    parser.add_argument("--host-version", required=True)
    parser.add_argument("--section", default="Applications")
    parser.add_argument("--homepage", default="https://github.com/Torrekie/Battman")
    parser.add_argument("--maintainer", default="Torrekie <me@torrekie.dev>")
    parser.add_argument("--control-template", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()

    epoch = source_date_epoch(arguments.source_date_epoch)
    plugin = require_input_directory(arguments.plugin, ".battman")
    output = require_new_output(arguments.output, ".deb")
    version = require_package_version(arguments.version, "plug-in Debian version")
    host_version = require_version(arguments.host_version, "host version")
    repo_root = Path(__file__).resolve().parents[2]
    verifier = repo_root / "PluginSDK/Tools/Package/verify-plugin-package.py"
    verification = json.loads(run([sys.executable, str(verifier), str(plugin)]).stdout)
    plugin_identifier = require_identifier(verification.get("pluginIdentifier", ""), "plug-in identifier")
    manifest = json.loads((plugin / "Manifest.json").read_text(encoding="utf-8"))
    if manifest.get("pluginIdentifier") != plugin_identifier:
        raise ReleaseError("portable verification and manifest identities differ")
    display_name = manifest.get("displayName")
    if not isinstance(display_name, str) or not display_name or len(display_name) > 128:
        raise ReleaseError("plug-in display name is invalid")
    if any("\n" in value or "\r" in value for value in
           (display_name, arguments.section, arguments.homepage, arguments.maintainer)):
        raise ReleaseError("Debian metadata cannot contain newlines")
    architecture, install_root = LAYOUTS[arguments.flavor]
    template = (arguments.control_template or repo_root / "Packaging/Debian/Plugins/control.in").resolve()

    temporary = temporary_sibling(output.parent, ".battman-plugin-deb-")
    try:
        root = temporary / "root"
        destination = root / install_root / f"{plugin_identifier}.battman"
        copy_tree_normalized(plugin, destination, epoch)
        control = render_template(template, {
            "PACKAGE": plugin_identifier,
            "NAME": display_name,
            "VERSION": version,
            "ARCHITECTURE": architecture,
            "SECTION": arguments.section,
            "INSTALLED_SIZE": str(tree_size_kib(destination)),
            "HOST_VERSION": host_version,
            "HOMEPAGE": arguments.homepage,
            "MAINTAINER": arguments.maintainer,
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
    except (OSError, json.JSONDecodeError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
