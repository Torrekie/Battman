#!/usr/bin/env python3
"""Generate deterministic unsigned SLSA-style in-toto provenance."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from release_common import ReleaseError, require_git_commit, require_new_output, sha256_file, source_date_epoch, write_normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", action="append", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository", default="https://github.com/Torrekie/Battman")
    parser.add_argument("--builder-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    commit = require_git_commit(arguments.commit)
    output = require_new_output(arguments.output)
    subjects = []
    for raw in arguments.asset:
        asset = raw.expanduser().resolve()
        if not asset.is_file() or asset.is_symlink() or asset.parent != output.parent:
            raise ReleaseError("provenance subjects must be files in the release directory")
        subjects.append({"name": asset.name, "digest": {"sha256": sha256_file(asset)}})
    subjects.sort(key=lambda value: value["name"].encode("utf-8"))
    timestamp = dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")
    statement = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": subjects,
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://github.com/Torrekie/Battman/tree/main/Scripts/Release",
                "externalParameters": {"sourceDateEpoch": epoch},
                "internalParameters": {},
                "resolvedDependencies": [{
                    "uri": f"git+{arguments.repository}@{commit}",
                    "digest": {"gitCommit": commit},
                }],
            },
            "runDetails": {
                "builder": {"id": arguments.builder_id},
                "metadata": {"invocationId": f"{commit}:{epoch}", "startedOn": timestamp, "finishedOn": timestamp},
                "byproducts": [],
            },
        },
    }
    data = (json.dumps(statement, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    write_normalized(output, data, epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
