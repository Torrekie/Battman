#!/usr/bin/env python3
"""Validate Battman's conservative release compatibility claim."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

from release_common import ReleaseError, require_version


EXPECTED_POLICY = {
    "ios12PhysicalDeviceRequiredForCurrentGoal": False,
    "minimumRuntimeEvidence": "simulator-and-arm64-ios12-compile",
    "trollStoreDataDirectoryNativeLoadingClaimed": False,
    "trollStoreThirdPartyActivation": "replacement-tipa-only",
}
EXPECTED_CHANNELS = {
    "jailbroken-rooted": {
        "artifactArchitecture": "iphoneos-arm",
        "documentedMinimumIOSVersion": "12.0",
        "nativePluginActivation": "verified-package-on-next-launch",
        "supportStatus": "release-contract",
        "deviceCoverage": "supplemental-rooted-ios14-package-integrity",
    },
    "jailbroken-rootless": {
        "artifactArchitecture": "iphoneos-arm64",
        "documentedMinimumIOSVersion": "15.0",
        "nativePluginActivation": "verified-package-on-next-launch",
        "supportStatus": "release-contract",
        "deviceCoverage": "not-a-complete-device-matrix",
    },
    "trollstore": {
        "artifactArchitecture": "tipa",
        "documentedMinimumIOSVersion": "14.0",
        "nativePluginActivation": "replacement-tipa-only",
        "supportStatus": "release-contract",
        "deviceCoverage": "outer-signing-and-install-not-proven-by-local-artifact-tests",
    },
}
EXPECTED_EVIDENCE = {
    "arm64-ios12-compile": (
        "verified", "Battman/Makefile"
    ),
    "iphone-ios15-simulator-ui": (
        "verified", "Tests/Simulator/BTAnalyticsCardsScreenshotHarness.m"
    ),
    "ipad-ios15-simulator-ui": (
        "verified", "Tests/Simulator/BTAnalyticsCardsScreenshotHarness.m"
    ),
    "rooted-ios14-package-integrity": (
        "verified-limited", "Tests/Device/run-analytics-rooted-preflight.sh"
    ),
    "trollstore-replacement-artifact": (
        "verified-artifact-only", "Scripts/Release/build-tipa.py"
    ),
    "a11-ios12-through-ios17": (
        "community-reported", "docs/plugin-system.md"
    ),
}
EXPECTED_UNSUPPORTED_CLAIMS = {
    "independent-device-certification-for-every-a11-or-newer-device-on-ios12-through-ios17",
    "trollstore-data-directory-native-loading",
    "automatic-resigning-or-installation-by-battman",
    "apple-supported-general-purpose-ios-plugin-loading",
}
EXPECTED_CARDS = {
    "com.torrekie.battman.analytics.live": (
        "embedded",
        [
            "battery.state-of-charge.percent",
            "battery.charging.state",
            "system.low-power-mode",
            "battery.power.net.watts",
            "battery.power.average.watts",
            "battery.current.average.milliamps",
            "battery.temperature.average.celsius",
        ],
        "host-snapshot-and-foreground-short-window-no-persistent-history",
    ),
    "com.torrekie.battman.analytics.capacity": (
        "embedded",
        [
            "battery.capacity.full-charge.milliamp-hours",
            "battery.capacity.design.milliamp-hours",
            "full-charge-capacity.milliamp-hours",
            "design-capacity.milliamp-hours",
            "cycle-count",
        ],
        "host-capacity-snapshot-or-host-only-normalized-powerlog-history",
    ),
    "com.torrekie.battman.analytics.cells": (
        "embedded",
        [
            "cell-voltage.0.millivolts",
            "cell-voltage.1.millivolts",
            "cell-voltage.2.millivolts",
        ],
        "host-only-normalized-main-battery-cell-voltage-history-or-validated-live",
    ),
    "com.torrekie.battman.analytics.session": (
        "embedded",
        [
            "soc.percent",
            "temperature.celsius",
            "current.milliamps",
            "external-connected",
            "is-charging",
            "fully-charged",
        ],
        "host-only-normalized-connected-powerlog-session",
    ),
    "com.torrekie.battman.analytics.discharge": (
        "embedded",
        [
            "soc.percent",
            "battery-power.watts",
            "external-connected",
        ],
        "host-only-normalized-unplugged-powerlog-session",
    ),
    "com.torrekie.battman.analytics.events": (
        "embedded",
        [
            "external-connected",
            "is-charging",
            "fully-charged",
            "not-charging-reason.code",
        ],
        "host-only-normalized-powerlog-states-and-sampled-transitions",
    ),
    "com.torrekie.battman.analytics.path": (
        "embedded",
        [
            "battery-power.watts",
            "input-power.watts",
            "power-budget.watts",
            "power-target.watts",
        ],
        "host-only-normalized-powerlog-measurement-points-not-an-efficiency-model",
    ),
    "com.torrekie.battman.analytics.dwell": (
        "embedded",
        [
            "soc.percent",
            "temperature.celsius",
            "external-connected",
        ],
        "host-only-normalized-powerlog-time-weighted-intervals",
    ),
    "com.torrekie.battman.analytics.compare": (
        "embedded",
        [
            "soc.percent",
            "external-connected",
            "temperature.celsius",
        ],
        "host-only-compatible-complete-connected-powerlog-sessions",
    ),
    "com.torrekie.battman.analytics.rhythm": (
        "embedded",
        [
            "soc.percent",
            "external-connected",
        ],
        "host-only-normalized-unplugged-powerlog-calendar-intervals",
    ),
    "com.torrekie.battman.plugin.charge-gauge": (
        "source-example",
        ["battery.state-of-charge.percent", "battery.charging.state"],
        "host-snapshot-only-no-direct-hardware-access",
    ),
}
TOP_LEVEL_FIELDS = {
    "schemaVersion", "releaseVersion", "host", "validationPolicy",
    "installationChannels", "evidence", "analyticsCards", "unsupportedClaims",
}
HOST_FIELDS = {
    "architecture", "declaredHardwareBaseline", "fullDeviceMatrixCompleted",
    "minimumIOSVersion",
}
CHANNEL_FIELDS = {"identifier", *next(iter(EXPECTED_CHANNELS.values())).keys()}
EVIDENCE_FIELDS = {"identifier", "reference", "scope", "status"}
CARD_FIELDS = {
    "identifier", "delivery", "requiredMetrics", "availability", "hardwareBoundary",
}
METRIC_PATTERN = re.compile(r'^#define\s+BAAnalyticsMetric[A-Za-z0-9_]+\s+@"([^"]+)"$', re.MULTILINE)
HISTORY_METRIC_PATTERN = re.compile(r'^#define\s+BAAnalyticsHistory[A-Za-z0-9_]+\s+@"([^"]+)"$', re.MULTILINE)
FAMILY_PATTERN = re.compile(r'^#define\s+BAAnalyticsFamily[A-Za-z0-9_]+\s+@"([^"]+)"$', re.MULTILINE)


def _regular_json(path: Path, label: str) -> dict[str, Any]:
    lexical = path.expanduser().absolute()
    if not lexical.is_file() or lexical.is_symlink() or lexical.stat().st_size > 512 * 1024:
        raise ReleaseError(f"{label} must be one bounded regular JSON file")
    try:
        value = json.loads(lexical.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise ReleaseError(f"{label} must contain one object")
    return value


def _bounded_line(value: Any, label: str, maximum: int = 512) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum or "\n" in value or "\r" in value:
        raise ReleaseError(f"{label} must be one bounded non-empty line")
    return value


def _unique_records(value: Any, fields: set[str], label: str) -> dict[str, dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise ReleaseError(f"{label} must be a non-empty array")
    result: dict[str, dict[str, Any]] = {}
    for item in value:
        if not isinstance(item, dict) or set(item) != fields:
            raise ReleaseError(f"{label} contains a malformed record")
        identifier = _bounded_line(item.get("identifier"), f"{label} identifier", 255)
        if identifier in result:
            raise ReleaseError(f"{label} contains duplicate identifier {identifier}")
        result[identifier] = item
    return result


def validate_compatibility_matrix_value(
    value: dict[str, Any], expected_version: str
) -> dict[str, Any]:
    version = require_version(expected_version)
    if set(value) != TOP_LEVEL_FIELDS or value.get("schemaVersion") != 1:
        raise ReleaseError("compatibility matrix has an unsupported top-level shape")
    if value.get("releaseVersion") != version:
        raise ReleaseError("compatibility matrix releaseVersion differs from the release")

    host = value.get("host")
    if not isinstance(host, dict) or set(host) != HOST_FIELDS or host != {
        "architecture": "arm64",
        "declaredHardwareBaseline": "Apple A11 or newer",
        "fullDeviceMatrixCompleted": False,
        "minimumIOSVersion": "12.0",
    }:
        raise ReleaseError("compatibility matrix host claim drifted from the approved boundary")
    if value.get("validationPolicy") != EXPECTED_POLICY:
        raise ReleaseError("compatibility matrix validation policy drifted from the approved boundary")

    channels = _unique_records(value.get("installationChannels"), CHANNEL_FIELDS, "installation channels")
    if set(channels) != set(EXPECTED_CHANNELS):
        raise ReleaseError("compatibility matrix installation-channel set is incomplete")
    for identifier, expected in EXPECTED_CHANNELS.items():
        actual = dict(channels[identifier])
        actual.pop("identifier")
        if actual != expected:
            raise ReleaseError(f"compatibility matrix channel claim drifted: {identifier}")

    evidence = _unique_records(value.get("evidence"), EVIDENCE_FIELDS, "compatibility evidence")
    if {
        identifier: (item["status"], item["reference"])
        for identifier, item in evidence.items()
    } != EXPECTED_EVIDENCE:
        raise ReleaseError("compatibility evidence statuses drifted or overstate verification")
    for identifier, item in evidence.items():
        _bounded_line(item["scope"], f"compatibility evidence scope {identifier}")
        reference = _bounded_line(item["reference"], f"compatibility evidence reference {identifier}")
        if reference.startswith("/") or ".." in Path(reference).parts or "\\" in reference:
            raise ReleaseError(f"compatibility evidence reference is unsafe: {reference}")

    cards = _unique_records(value.get("analyticsCards"), CARD_FIELDS, "Analytics cards")
    if set(cards) != set(EXPECTED_CARDS):
        raise ReleaseError("compatibility matrix Analytics card set is incomplete")
    for identifier, card in cards.items():
        if card["delivery"] not in ("embedded", "official-plugin", "source-example"):
            raise ReleaseError(f"Analytics card has an invalid delivery class: {identifier}")
        metrics = card["requiredMetrics"]
        if not isinstance(metrics, list) or not metrics or any(
            not isinstance(metric, str) or not metric or len(metric) > 255 for metric in metrics
        ) or len(metrics) != len(set(metrics)):
            raise ReleaseError(f"Analytics card has invalid required metrics: {identifier}")
        _bounded_line(card["availability"], f"Analytics availability {identifier}", 1024)
        _bounded_line(card["hardwareBoundary"], f"Analytics hardware boundary {identifier}")
        expected_delivery, expected_metrics, expected_boundary = EXPECTED_CARDS[identifier]
        if (
            card["delivery"] not in ({"source-example", "official-plugin"} if expected_delivery == "source-example" else {expected_delivery})
            or card["requiredMetrics"] != expected_metrics
            or card["hardwareBoundary"] != expected_boundary
        ):
            raise ReleaseError(f"Analytics compatibility claim drifted: {identifier}")

    unsupported = value.get("unsupportedClaims")
    if not isinstance(unsupported, list) or set(unsupported) != EXPECTED_UNSUPPORTED_CLAIMS or len(unsupported) != len(set(unsupported)):
        raise ReleaseError("compatibility matrix unsupported-claim set is incomplete")
    return value


def load_compatibility_matrix(path: Path, expected_version: str) -> dict[str, Any]:
    return validate_compatibility_matrix_value(
        _regular_json(path, "compatibility matrix"), expected_version
    )


def validate_repository_compatibility_matrix(
    repo: Path,
    expected_version: str,
) -> dict[str, Any]:
    """Validate public source, channel, and compatibility contracts."""
    repo = repo.expanduser().resolve()
    matrix_path = repo / "Packaging/Release/compatibility-matrix.json"
    value = load_compatibility_matrix(matrix_path, expected_version)
    release_matrix = _regular_json(repo / "Packaging/Release/release-matrix.json", "release matrix")
    if release_matrix.get("minimumIOSVersion") != value["host"]["minimumIOSVersion"]:
        raise ReleaseError("release and compatibility matrices disagree on minimum iOS")
    if release_matrix.get("compatibilityMatrix") != "compatibility-matrix.json":
        raise ReleaseError("release matrix does not select the canonical compatibility matrix")

    selection = release_matrix.get("officialPluginSelection")
    if not isinstance(selection, dict):
        raise ReleaseError("release matrix official plug-in selection is missing")
    embedded = selection.get("embeddedAnalyticsCards")
    separate = selection.get("separatelyShipped")
    if not isinstance(embedded, list) or not isinstance(separate, list):
        raise ReleaseError("release matrix card selection is malformed")
    if len(embedded + separate) != len(set(embedded + separate)):
        raise ReleaseError("release matrix card selection is duplicated")
    expected_cards = {
        **{identifier: "embedded" for identifier in embedded},
        **{identifier: "official-plugin" for identifier in separate},
    }
    actual_cards = {card["identifier"]: card["delivery"] for card in value["analyticsCards"]
                    if card["delivery"] != "source-example"}
    if actual_cards != expected_cards:
        raise ReleaseError("compatibility matrix card delivery differs from the release selection")

    sdk_header = (repo / "PluginSDK/include/BAAnalyticsMetricSnapshot.h").read_text(encoding="utf-8")
    public_metrics = set(METRIC_PATTERN.findall(sdk_header))
    host_header = (repo / "Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h").read_text(encoding="utf-8")
    history_header = (repo / "Battman/Features/Analytics/Data/BAAnalyticsHistoryModels.h").read_text(encoding="utf-8")
    report_header = (repo / "Battman/Features/Analytics/Data/BAAnalyticsReport.h").read_text(encoding="utf-8")
    # Embedded canvases use internal snapshot and normalized history fields.
    # These host-only identifiers do not extend the public PluginSDK v1 API.
    host_metrics = public_metrics | set(METRIC_PATTERN.findall(host_header)) | set(HISTORY_METRIC_PATTERN.findall(history_header))
    families = set(FAMILY_PATTERN.findall(report_header))
    if {identifier.removeprefix("com.torrekie.battman.analytics.") for identifier in embedded} != families:
        raise ReleaseError("embedded Analytics selection differs from host report families")
    for card in value["analyticsCards"]:
        known_metrics = host_metrics if card["delivery"] == "embedded" else public_metrics
        if not set(card["requiredMetrics"]) <= known_metrics:
            raise ReleaseError(f"compatibility matrix names a metric outside its delivery surface: {card['identifier']}")
    for item in value["evidence"]:
        reference = repo / item["reference"]
        if not reference.is_file() or reference.is_symlink():
            raise ReleaseError(f"compatibility reference is missing: {item['reference']}")

    source_contracts = {
        "Battman/Makefile": "IPHONEOS_DEPLOYMENT_TARGET := 12.0",
        "OfficialPlugins/ChargeGauge/Makefile": "TARGET ?= arm64-apple-ios12.0",
        "PluginSDK/Templates/NativeAnalyticsCard/Makefile": "TARGET ?= arm64-apple-ios12.0",
        "Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.m":
            "return !self.allowsApplicationDataNativeLoading;",
    }
    for relative, fragment in source_contracts.items():
        if fragment not in (repo / relative).read_text(encoding="utf-8"):
            raise ReleaseError(f"compatibility source contract drifted: {relative}")
    return value


def compatibility_report(path: Path, value: dict[str, Any]) -> dict[str, Any]:
    data = path.read_bytes()
    statuses: dict[str, int] = {}
    for item in value["evidence"]:
        statuses[item["status"]] = statuses.get(item["status"], 0) + 1
    return {
        "schemaVersion": 1,
        "status": "passed",
        "releaseVersion": value["releaseVersion"],
        "matrix": path.as_posix(),
        "matrixSHA256": hashlib.sha256(data).hexdigest(),
        "analyticsCardCount": len(value["analyticsCards"]),
        "evidenceStatusCounts": statuses,
        "fullDeviceMatrixCompleted": value["host"]["fullDeviceMatrixCompleted"],
        "trollStoreDataDirectoryNativeLoadingClaimed":
            value["validationPolicy"]["trollStoreDataDirectoryNativeLoadingClaimed"],
    }
