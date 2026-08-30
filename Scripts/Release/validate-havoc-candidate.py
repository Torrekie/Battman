#!/usr/bin/env python3
"""Validate local Debian eligibility for manual owner-managed Havoc uploads."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from debian_archive import read_ar_members, read_control
from release_inspection import inspect_deb, inspect_plugin_deb
from host_build_identity import require_git_object_id
from release_common import (
    ReleaseError,
    require_git_commit,
    require_identifier,
    require_new_output,
    require_package_version,
    require_version,
    source_date_epoch,
    write_json,
)


CONTROL_LINE = re.compile(r"^([A-Za-z0-9-]+):[ ]?(.*)$")
HAVOC_SECTIONS = ("Applications", "Development", "Tweaks", "Themes")


def _debian_section(path: Path) -> str:
    try:
        text = read_control(read_ar_members(path.resolve())).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseError("Havoc Debian control metadata is not valid UTF-8") from error
    values: dict[str, str] = {}
    current: str | None = None
    for line in text.splitlines():
        match = CONTROL_LINE.fullmatch(line)
        if match:
            current = match.group(1)
            if current in values:
                raise ReleaseError(f"duplicate Debian control field: {current}")
            values[current] = match.group(2)
        elif line.startswith(" ") and current:
            values[current] += "\n" + line
        else:
            raise ReleaseError("malformed Debian control metadata")
    section = values.get("Section")
    if section not in HAVOC_SECTIONS:
        raise ReleaseError("Havoc Debian Section is missing or unsupported")
    return section


def _is_newer(candidate: str, published: str) -> bool:
    try:
        result = subprocess.run(["dpkg", "--compare-versions", candidate, "gt", published])
    except FileNotFoundError as error:
        raise ReleaseError("dpkg is required for authoritative Havoc version ordering") from error
    if result.returncode not in (0, 1):
        raise ReleaseError("dpkg rejected the Havoc version comparison")
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rooted-deb", required=True, type=Path)
    parser.add_argument("--rootless-deb", required=True, type=Path)
    parser.add_argument("--artifact-kind", choices=("host", "plugin"), default="host")
    parser.add_argument("--version", required=True)
    publication = parser.add_mutually_exclusive_group(required=True)
    publication.add_argument("--published-version")
    publication.add_argument("--initial-submission", action="store_true")
    parser.add_argument("--package", default="com.torrekie.battman")
    parser.add_argument("--host-version")
    parser.add_argument("--section", choices=HAVOC_SECTIONS)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--source-tree", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-date-epoch", type=int)
    arguments = parser.parse_args()
    epoch = source_date_epoch(arguments.source_date_epoch)
    package = require_identifier(arguments.package, "Havoc candidate package")
    section = arguments.section
    if arguments.artifact_kind == "host":
        version = require_version(arguments.version)
        if section is None:
            section = "Applications"
        if section != "Applications":
            raise ReleaseError("host Havoc candidates must use Section: Applications")
        if arguments.initial_submission:
            raise ReleaseError(
                "host Havoc candidates require an explicit --published-version"
            )
        if arguments.host_version is not None:
            raise ReleaseError("host Havoc candidates do not accept --host-version")
        published = (
            require_version(arguments.published_version, "published version")
            if arguments.published_version is not None else None
        )
    else:
        if section is None:
            raise ReleaseError(
                "plug-in Havoc candidates require an explicit --section classification"
            )
        version = require_package_version(arguments.version, "plug-in version")
        if package == "com.torrekie.battman":
            raise ReleaseError("plug-in Havoc candidates require their plug-in package identifier")
        if arguments.host_version is None:
            raise ReleaseError("plug-in Havoc candidates require --host-version")
        host_version = require_version(arguments.host_version, "host version")
        published = (
            require_package_version(arguments.published_version, "published plug-in version")
            if arguments.published_version is not None else None
        )
    if published is not None and not _is_newer(version, published):
        raise ReleaseError("Havoc candidate version must be newer than the explicit published version")
    commit = require_git_commit(arguments.commit)
    source_tree = require_git_object_id(arguments.source_tree, "source tree")
    output = require_new_output(arguments.output, ".json")
    if arguments.artifact_kind == "host":
        records = [
            inspect_deb(
                arguments.rooted_deb, "rooted", version, package,
                commit=commit, source_tree=source_tree,
            ),
            inspect_deb(
                arguments.rootless_deb, "rootless", version, package,
                commit=commit, source_tree=source_tree,
            ),
        ]
    else:
        records = [
            inspect_plugin_deb(
                arguments.rooted_deb, "rooted", version, package, host_version,
            ),
            inspect_plugin_deb(
                arguments.rootless_deb, "rootless", version, package, host_version,
            ),
        ]
    for path, flavor in (
        (arguments.rooted_deb, "rooted"),
        (arguments.rootless_deb, "rootless"),
    ):
        if _debian_section(path) != section:
            raise ReleaseError(
                f"{flavor} Havoc Debian Section differs from --section"
            )
    write_json(output, {
        "schemaVersion": 1,
        "status": "candidate-only-not-uploaded",
        "candidateEligibility": "eligible-for-manual-owner-submission",
        "artifactKind": f"{arguments.artifact_kind}-debian-pair",
        "package": package,
        "section": section,
        "version": version,
        "publishedVersionCompared": published,
        "publicationState": "not-recorded-by-validator",
        "sourceCommit": commit,
        "sourceTree": source_tree,
        "artifacts": records,
        "manualOwnerUploadOnly": True,
        "automaticUploadPerformed": False,
        "ownerApprovalRequired": True,
        "havocClassificationDecisionRequired": True,
        "dualHostingReviewRequired": True,
    }, epoch)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ReleaseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
