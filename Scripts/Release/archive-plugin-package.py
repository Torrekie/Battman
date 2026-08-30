#!/usr/bin/env python3
"""Wrap one signed .battman directory in a deterministic download archive."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    copy_tree_normalized,
    deterministic_zip,
    remove_staged_tree,
    require_identifier,
    require_input_directory,
    require_new_output,
    require_package_version,
    run,
    source_date_epoch,
    temporary_sibling,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    plugin = require_input_directory(arguments.plugin, ".battman")
    output = require_new_output(arguments.output, ".zip")
    if not output.name.endswith(".battman.zip"):
        raise ReleaseError("plug-in transport archive must end in .battman.zip")

    verifier = Path(__file__).resolve().parents[2] / "PluginSDK/Tools/Package/verify-plugin-package.py"
    verification = json.loads(run([sys.executable, str(verifier), str(plugin)]).stdout)
    try:
        manifest = json.loads((plugin / "Manifest.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError("plug-in transport has invalid manifest metadata") from error
    raw_identifier = manifest.get("pluginIdentifier")
    raw_version = manifest.get("displayVersion")
    if not isinstance(raw_identifier, str) or not isinstance(raw_version, str):
        raise ReleaseError("plug-in transport identity is incomplete")
    identifier = require_identifier(raw_identifier, "plug-in identifier")
    version = require_package_version(raw_version, "plug-in version")
    if verification.get("pluginIdentifier") != identifier:
        raise ReleaseError("portable plug-in verification returned a different identity")
    expected_name = f"{identifier}_{version}.battman.zip"
    if output.name != expected_name:
        raise ReleaseError(f"plug-in transport archive must be named {expected_name}")

    temporary = temporary_sibling(output.parent, ".battman-plugin-archive-")
    try:
        root = temporary / "root"
        root.mkdir(mode=0o755)
        copy_tree_normalized(plugin, root / f"{identifier}.battman", epoch)
        deterministic_zip(root, output, epoch)
    finally:
        if temporary.exists():
            remove_staged_tree(temporary, output.parent)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
