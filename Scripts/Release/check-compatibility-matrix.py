#!/usr/bin/env python3
"""Check the release compatibility matrix against repository contracts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from compatibility_matrix import compatibility_report, validate_repository_compatibility_matrix
from release_common import ReleaseError, require_version


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--version")
    arguments = parser.parse_args()
    repo = arguments.repo.expanduser().resolve()
    version = require_version(arguments.version or (repo / "VERSION").read_text(encoding="utf-8").strip())
    path = repo / "Packaging/Release/compatibility-matrix.json"
    value = validate_repository_compatibility_matrix(repo, version)
    report = compatibility_report(path, value)
    report["matrix"] = path.relative_to(repo).as_posix()
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeDecodeError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
