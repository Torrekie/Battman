#!/usr/bin/env python3
"""Render deterministic release notes from reviewed local metadata."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    require_git_commit,
    require_new_output,
    require_version,
    source_date_epoch,
    write_normalized,
)


DEFAULT_GATES = "- None recorded by the release operator."


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--known-gate", action="append", default=[])
    parser.add_argument("--template", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    version = require_version(arguments.version)
    commit = require_git_commit(arguments.commit)
    output = require_new_output(arguments.output, ".md")
    repo_root = Path(__file__).resolve().parents[2]
    template = (arguments.template or repo_root / "Packaging/Release/release-notes.md.in").resolve()
    gates = arguments.known_gate
    if any(not value or "\n" in value or "\r" in value for value in gates):
        raise ReleaseError("known-gate values must be non-empty single lines")
    rendered_gates = "\n".join(f"- {value}" for value in gates) if gates else DEFAULT_GATES
    text = template.read_text(encoding="utf-8")
    for marker, value in {
        "@VERSION@": version,
        "@COMMIT@": commit,
        "@KNOWN_GATES@": rendered_gates,
    }.items():
        if text.count(marker) != 1:
            raise ReleaseError(f"release-note template must contain exactly one {marker}")
        text = text.replace(marker, value)
    write_normalized(output, text.encode("utf-8"), epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
