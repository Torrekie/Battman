#!/usr/bin/env python3
"""Render the example manifest template for an existing publisher key.

This tool validates a public-key identifier. It never creates or reads private
key material and never signs a package.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "Package"))
from battman_plugin_format import PluginFormatError, validate_author_metadata, validate_display_name


KEY_IDENTIFIER = re.compile(r"^[0-9a-f]{64}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--publisher-key-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--template",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "Examples"
        / "AnalyticsCard"
        / "ManifestTemplate.json.in",
    )
    arguments = parser.parse_args()
    if not KEY_IDENTIFIER.fullmatch(arguments.publisher_key_id):
        parser.error("publisher key id must be 64 lowercase hexadecimal characters")
    if arguments.output.exists() or not arguments.output.parent.is_dir():
        parser.error("output must not exist and its parent directory must exist")
    template = arguments.template.read_text(encoding="utf-8")
    rendered = template.replace("@PUBLISHER_KEY_ID@", arguments.publisher_key_id)
    value = json.loads(rendered)
    try:
        validate_display_name(value)
        validate_author_metadata(value)
    except PluginFormatError as error:
        parser.error(str(error))
    if "files" in value or rendered.count(arguments.publisher_key_id) != 2:
        parser.error("manifest template structure is not suitable for package construction")
    arguments.output.write_text(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
