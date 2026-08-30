#!/usr/bin/env python3
"""Compatibility entry point for the release-inspection module."""

import plistlib
import sys
import tarfile
import zipfile

from release_common import ReleaseError
from release_inspection import main


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        plistlib.InvalidFileException,
        tarfile.TarError,
        zipfile.BadZipFile,
        ReleaseError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
