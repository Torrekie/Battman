#!/usr/bin/env python3
"""Verify that a linked host carries the current repository identity."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


RELEASE_TOOLS = Path(__file__).resolve().parents[1] / "Release"
sys.path.insert(0, str(RELEASE_TOOLS))

from host_build_identity import require_repository_identity  # noqa: E402
from release_common import ReleaseError  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--product-identifier", required=True)
    arguments = parser.parse_args()
    identity = require_repository_identity(
        arguments.executable,
        arguments.repo,
        arguments.version,
        arguments.configuration,
        arguments.product_identifier,
    )
    print(json.dumps(identity, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
