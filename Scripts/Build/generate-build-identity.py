#!/usr/bin/env python3
"""Generate the canonical host identity consumed by the Mach-O linker."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


RELEASE_TOOLS = Path(__file__).resolve().parents[1] / "Release"
sys.path.insert(0, str(RELEASE_TOOLS))

from host_build_identity import write_repository_build_identity  # noqa: E402
from release_common import ReleaseError  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--product-identifier", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    identity = write_repository_build_identity(
        arguments.output,
        arguments.repo,
        arguments.version,
        arguments.configuration,
        arguments.product_identifier,
    )
    print(arguments.output.expanduser().absolute())
    if identity["sourceDirty"]:
        print("warning: generated identity marks the source worktree dirty", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
