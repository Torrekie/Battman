#!/usr/bin/env python3
"""Attach and verify an offline checksum signature without overwriting a candidate."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import sys
from pathlib import Path

from release_common import (
    ReleaseError,
    copy_tree_normalized,
    remove_staged_tree,
    require_input_directory,
    require_new_output,
    run,
    source_date_epoch,
    temporary_sibling,
)


def _regular_file(path: Path, label: str) -> Path:
    lexical = path.expanduser().absolute()
    entry = lexical.lstat()
    if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1 or entry.st_size > 1024:
        raise ReleaseError(f"{label} must be one regular file")
    return lexical.resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--signature", required=True, type=Path)
    parser.add_argument("--expected-key-id", required=True)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()

    epoch = source_date_epoch(arguments.source_date_epoch)
    candidate = require_input_directory(arguments.candidate)
    candidate_signature = candidate / "SHA256SUMS.p256.sig"
    if candidate_signature.exists() or candidate_signature.is_symlink():
        raise ReleaseError("candidate already contains a checksum signature")
    signature = _regular_file(arguments.signature, "offline checksum signature")
    output = require_new_output(arguments.output_directory)
    if candidate == output.parent or candidate in output.parent.parents:
        raise ReleaseError("final release output must remain outside the unsigned candidate")
    if signature == candidate or candidate in signature.parents:
        raise ReleaseError("returned signature must remain outside the unsigned candidate")
    scripts = Path(__file__).resolve().parent
    run([
        sys.executable,
        str(scripts / "verify-release-directory.py"),
        str(candidate),
        "--allow-missing-offline-signature",
    ])
    temporary = temporary_sibling(output.parent, ".battman-release-finalize-")
    try:
        release = temporary / "release"
        copy_tree_normalized(candidate, release, epoch)
        signature_output = release / "SHA256SUMS.p256.sig"
        shutil.copyfile(signature, signature_output, follow_symlinks=False)
        os.chmod(signature_output, 0o644)
        os.utime(signature_output, (epoch, epoch), follow_symlinks=False)
        key_identifier = run([
            sys.executable,
            str(scripts / "inspect-checksum-public-key.py"),
            str(release / "SHA256SUMS.p256.pub"),
            "--expected-key-id",
            arguments.expected_key_id,
        ]).stdout.strip()
        run([
            sys.executable,
            str(scripts / "sign-checksums.py"),
            "--public-key",
            str(release / "SHA256SUMS.p256.pub"),
            "--checksums",
            str(release / "SHA256SUMS"),
            "--signature",
            str(signature_output),
        ])
        run([sys.executable, str(scripts / "verify-checksums.py"), str(
            release / "SHA256SUMS"
        )])
        run([sys.executable, str(scripts / "verify-release-directory.py"), str(release)])
        os.utime(release, (epoch, epoch), follow_symlinks=False)
        os.rename(release, output)
    finally:
        if temporary.exists():
            remove_staged_tree(temporary, output.parent)
    print(key_identifier)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
