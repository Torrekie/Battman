#!/usr/bin/env python3
"""Create an Analytics card project from the SDK example.

No key is created and no package is signed. The generated manifest retains an
explicit publisher-key placeholder until the author supplies an existing key.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "Package"))
from battman_plugin_format import (
    PluginFormatError,
    validate_author_metadata,
    validate_display_name,
)


IDENTIFIER = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
    r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$"
)
SOURCE_FILES = (
    "BUILD_VERSION",
    "BTAnalyticsExamplePlugin.h",
    "BTAnalyticsExamplePlugin.m",
    "Info.plist",
    "ManifestTemplate.json.in",
)


def replace_text(path: Path, replacements: tuple[tuple[str, str], ...]) -> None:
    text = path.read_text(encoding="utf-8")
    for old, new in replacements:
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin-id", required=True)
    parser.add_argument("--card-id", required=True)
    parser.add_argument("--display-name", required=True)
    parser.add_argument("--author-name")
    parser.add_argument("--homepage-url")
    parser.add_argument("--support-email")
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    for label, value in (("plugin id", arguments.plugin_id), ("card id", arguments.card_id)):
        if not IDENTIFIER.fullmatch(value) or len(value) > 255:
            parser.error(f"{label} must be a lowercase reverse-DNS identifier")
    if not arguments.card_id.startswith(arguments.plugin_id + "."):
        parser.error("card id must be namespaced beneath the plug-in id")
    try:
        validate_display_name({"displayName": arguments.display_name})
    except PluginFormatError as error:
        parser.error(str(error))
    if (arguments.homepage_url or arguments.support_email) and not arguments.author_name:
        parser.error("--author-name is required when author contact metadata is supplied")
    author_metadata = None
    if arguments.author_name:
        author_metadata = {"name": arguments.author_name}
        if arguments.homepage_url:
            author_metadata["homepageURL"] = arguments.homepage_url
        if arguments.support_email:
            author_metadata["supportEmail"] = arguments.support_email
        try:
            validate_author_metadata({"author": author_metadata})
        except PluginFormatError as error:
            parser.error(str(error))
    output = arguments.output.resolve()
    if output.exists() or not output.parent.is_dir():
        parser.error("output must not exist and its parent directory must exist")

    sdk_root = Path(__file__).resolve().parents[1]
    example = sdk_root / "Examples" / "AnalyticsCard"
    template = sdk_root / "Templates" / "NativeAnalyticsCard" / "Makefile"
    output.mkdir(mode=0o755)
    try:
        for name in SOURCE_FILES:
            source = example / name
            if source.is_symlink() or not source.is_file():
                raise RuntimeError(f"SDK template file is missing or unsafe: {name}")
            shutil.copy2(source, output / name, follow_symlinks=False)
        shutil.copy2(template, output / "Makefile", follow_symlinks=False)
        replacements = (
            ("com.torrekie.battman.example.analytics.charge", arguments.card_id),
            ("com.torrekie.battman.example.analytics", arguments.plugin_id),
            ("Battman Analytics SDK Example", arguments.display_name),
            ("SDK Charge Example", arguments.display_name),
            ("PLUGIN_IDENTIFIER ?= com.example.battman.analytics-card",
             f"PLUGIN_IDENTIFIER ?= {arguments.plugin_id}"),
        )
        for path in output.iterdir():
            if path.is_file():
                replace_text(path, replacements)
        if author_metadata:
            manifest_path = output / "ManifestTemplate.json.in"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["author"] = author_metadata
            manifest_path.write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
    except Exception:
        shutil.rmtree(output, ignore_errors=True)
        raise
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
