#!/usr/bin/env python3
"""Regression tests for conservative compatibility and support claims."""

from __future__ import annotations

import copy
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/Release"))

from compatibility_matrix import (  # noqa: E402
    load_compatibility_matrix,
    validate_compatibility_matrix_value,
    validate_repository_compatibility_matrix,
)
from release_common import ReleaseError  # noqa: E402


MATRIX = ROOT / "Packaging/Release/compatibility-matrix.json"


def expect_failure(action, label: str) -> None:
    try:
        action()
    except ReleaseError:
        return
    raise AssertionError(f"expected compatibility hard failure: {label}")


def main() -> int:
    value = validate_repository_compatibility_matrix(ROOT, "1.1.0")
    assert load_compatibility_matrix(MATRIX, "1.1.0") == value
    assert value["host"] == {
        "architecture": "arm64",
        "declaredHardwareBaseline": "Apple A11 or newer",
        "fullDeviceMatrixCompleted": False,
        "minimumIOSVersion": "12.0",
    }
    assert value["validationPolicy"]["trollStoreThirdPartyActivation"] == "replacement-tipa-only"
    assert value["validationPolicy"]["trollStoreDataDirectoryNativeLoadingClaimed"] is False
    statuses = {item["identifier"]: item["status"] for item in value["evidence"]}
    assert statuses["a11-ios12-through-ios17"] == "community-reported"
    assert statuses["rooted-ios14-package-integrity"] == "verified-limited"
    assert len(value["analyticsCards"]) == 7

    wrong_version = copy.deepcopy(value)
    wrong_version["releaseVersion"] = "1.1.0.1"
    expect_failure(
        lambda: validate_compatibility_matrix_value(wrong_version, "1.1.0"),
        "version drift",
    )
    direct_trollstore = copy.deepcopy(value)
    direct_trollstore["validationPolicy"]["trollStoreDataDirectoryNativeLoadingClaimed"] = True
    expect_failure(
        lambda: validate_compatibility_matrix_value(direct_trollstore, "1.1.0"),
        "unsupported TrollStore direct loading",
    )
    overclaim = copy.deepcopy(value)
    for item in overclaim["evidence"]:
        if item["identifier"] == "a11-ios12-through-ios17":
            item["status"] = "verified"
    expect_failure(
        lambda: validate_compatibility_matrix_value(overclaim, "1.1.0"),
        "community report promoted to verified evidence",
    )
    missing_unsupported = copy.deepcopy(value)
    missing_unsupported["unsupportedClaims"].pop()
    expect_failure(
        lambda: validate_compatibility_matrix_value(missing_unsupported, "1.1.0"),
        "missing unsupported-claim boundary",
    )
    print("Conservative device, channel, TrollStore, and Analytics compatibility claims passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
