#!/usr/bin/env python3
"""Verify a strict SHA256SUMS file without leaving its release directory."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from release_common import ReleaseError, sha256_file


LINE = re.compile(rb"([0-9a-f]{64})  ([^\r\n/]+)\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("checksums", type=Path)
    arguments = parser.parse_args()
    path = arguments.checksums.expanduser().resolve()
    if not path.is_file() or path.is_symlink():
        raise ReleaseError("checksums input must be a regular file")
    data = path.read_bytes()
    offset = 0
    seen: set[str] = set()
    count = 0
    while offset < len(data):
        match = LINE.match(data, offset)
        if not match:
            raise ReleaseError("malformed SHA256SUMS line")
        digest = match.group(1).decode("ascii")
        try:
            name = match.group(2).decode("utf-8")
        except UnicodeDecodeError as error:
            raise ReleaseError("SHA256SUMS contains an invalid UTF-8 name") from error
        if name in seen or name in (".", "..") or "\\" in name:
            raise ReleaseError(f"duplicate or unsafe checksum name: {name!r}")
        seen.add(name)
        asset = path.parent / name
        if not asset.is_file() or asset.is_symlink() or sha256_file(asset) != digest:
            raise ReleaseError(f"checksum mismatch: {name}")
        count += 1
        offset = match.end()
    if count == 0:
        raise ReleaseError("SHA256SUMS is empty")
    print(f"verified {count} release assets")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
