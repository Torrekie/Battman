#!/usr/bin/env python3
"""Generate a deterministic SHA256SUMS file for explicit release assets."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from release_common import ReleaseError, require_new_output, sha256_file, source_date_epoch, write_normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", action="append", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    output = require_new_output(arguments.output)

    assets: list[Path] = []
    names: set[str] = set()
    for raw in arguments.asset:
        asset = raw.expanduser().resolve()
        if not asset.is_file() or asset.is_symlink():
            raise ReleaseError(f"checksum asset must be a regular file: {asset}")
        if asset.parent != output.parent:
            raise ReleaseError("checksum assets and output must share one release directory")
        if asset.name in names or "\n" in asset.name or "\r" in asset.name:
            raise ReleaseError(f"duplicate or unsafe artifact name: {asset.name!r}")
        names.add(asset.name)
        assets.append(asset)
    lines = [f"{sha256_file(path)}  {path.name}\n" for path in sorted(assets, key=lambda value: value.name.encode("utf-8"))]
    write_normalized(output, "".join(lines).encode("utf-8"), epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
