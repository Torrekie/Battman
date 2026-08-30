#!/usr/bin/env python3
"""Generate a deterministic CycloneDX release-artifact SBOM."""

from __future__ import annotations

import argparse
import datetime as dt
import sys
import tarfile
from pathlib import Path

from release_common import (
    PLUGIN_SDK_MIT_LICENSE_SHA256,
    ReleaseError,
    require_git_commit,
    require_new_output,
    require_plugin_sdk_license_data,
    sha256_file,
    source_date_epoch,
    write_json,
)


def _sdk_license(asset: Path, version: str) -> list[dict[str, dict[str, str]]]:
    expected_name = f"BattmanPluginSDK-{version}.tar.gz"
    if asset.name != expected_name:
        return []
    member_name = f"BattmanPluginSDK-{version}/LICENSE"
    try:
        with tarfile.open(asset, "r:gz") as archive:
            member = archive.getmember(member_name)
            if not member.isfile() or member.issym() or member.islnk() or member.size > 16 * 1024:
                raise ReleaseError("SDK archive LICENSE is not one bounded regular file")
            stream = archive.extractfile(member)
            if stream is None:
                raise ReleaseError("SDK archive LICENSE could not be read")
            require_plugin_sdk_license_data(stream.read(16 * 1024 + 1), "SDK archive LICENSE")
    except KeyError as error:
        raise ReleaseError("SDK archive is missing LICENSE") from error
    return [{"license": {"id": "MIT"}}]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", action="append", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    commit = require_git_commit(arguments.commit)
    output = require_new_output(arguments.output, ".json")
    components = []
    names: set[str] = set()
    for raw in arguments.asset:
        asset = raw.expanduser().resolve()
        if not asset.is_file() or asset.is_symlink() or asset.parent != output.parent:
            raise ReleaseError("SBOM assets must be regular files in the release directory")
        if asset.name in names:
            raise ReleaseError(f"duplicate SBOM asset: {asset.name}")
        names.add(asset.name)
        component = {
            "type": "file",
            "name": asset.name,
            "bom-ref": f"urn:battman:artifact:{asset.name}",
            "hashes": [{"alg": "SHA-256", "content": sha256_file(asset)}],
            "properties": [{"name": "battman:fileSize", "value": str(asset.stat().st_size)}],
        }
        licenses = _sdk_license(asset, arguments.version)
        if licenses:
            component["licenses"] = licenses
            component["properties"].append({
                "name": "battman:licenseFileSHA256",
                "value": PLUGIN_SDK_MIT_LICENSE_SHA256,
            })
        components.append(component)
    components.sort(key=lambda value: value["name"].encode("utf-8"))
    timestamp = dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")
    value = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{commit[:8]}-0000-4000-8000-{commit[-12:]}",
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "component": {
                "type": "application",
                "name": "Battman",
                "version": arguments.version,
                "bom-ref": f"pkg:github/Torrekie/Battman@{arguments.version}?vcs_url={commit}",
            },
            "properties": [{"name": "battman:sourceCommit", "value": commit}],
        },
        "components": components,
    }
    write_json(output, value, epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
