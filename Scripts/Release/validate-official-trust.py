#!/usr/bin/env python3
"""Validate public root policy and threshold-signed official trust metadata."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from official_trust import validate_official_trust
from release_common import ReleaseError


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plugin_trust", type=Path)
    arguments = parser.parse_args()
    result = validate_official_trust(arguments.plugin_trust)
    public_result = {
        "treeSHA256": result["treeSHA256"],
        "metadataSHA256": result["metadataSHA256"],
        "sequence": result["sequence"],
        "generatedAtUnixSeconds": result["generatedAtUnixSeconds"],
        "signatureThreshold": result["signatureThreshold"],
        "verifiedRootKeyIdentifiers": result["verifiedRootKeyIdentifiers"],
        "officialPublisherKeyIdentifiers": sorted(result["publishers"]),
        "revokedKeyIdentifiers": sorted(result["revokedKeyIdentifiers"]),
    }
    print(json.dumps(public_result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
