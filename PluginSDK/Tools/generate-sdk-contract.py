#!/usr/bin/env python3
"""Render or check Battman SDK contract v1 drift metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


CONTRACT_PATH = "SDKContractV1.json"
TRACKED_FILES = (
    "include/BattmanPluginABI.h",
    "include/BAAnalyticsCard.h",
    "include/BAAnalyticsMetricSnapshot.h",
    "schema/BattmanPluginManifestV1.schema.json",
    "schema/BattmanPluginTrustMetadataV1.schema.json",
    "TestSupport/ABI/v1-initial/BattmanPluginABI.h",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise ValueError(f"could not read {label} from the public ABI header")
    return match.group(1)


def render(sdk_root: Path) -> bytes:
    abi_text = (sdk_root / "include/BattmanPluginABI.h").read_text(encoding="utf-8")
    sdk_version = (sdk_root / "VERSION").read_text(encoding="ascii").strip()
    if sdk_version != "1":
        raise ValueError("SDKContractV1 requires PluginSDK/VERSION to remain 1")
    abi_version = int(require(r"^#define BT_PLUGIN_ABI_VERSION_1 ([0-9]+)u$", abi_text, "ABI version"))
    format_version = int(require(r"^#define BT_PLUGIN_FORMAT_VERSION_1 ([0-9]+)u$", abi_text, "package format version"))
    entry_point = require(r'^#define BT_PLUGIN_ENTRY_POINT_SYMBOL_V1 "([^"]+)"$', abi_text, "entry point")
    analytics_point = require(r'^#define BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1 "([^"]+)"$', abi_text, "Analytics extension point")
    hashes = {relative: sha256(sdk_root / relative) for relative in TRACKED_FILES}
    contract = {
        "contractSchemaVersion": 1,
        "sdkMajorVersion": int(sdk_version),
        "pluginABIVersion": abi_version,
        "packageFormatVersion": format_version,
        "entryPointSymbol": entry_point,
        "minimumDeployment": {"architecture": "arm64", "iOS": "12.0"},
        "extensionPoints": {
            "analyticsCard": {"identifier": analytics_point, "interfaceVersion": 1}
        },
        "lp64Layout": {
            "BTPluginErrorV1": {"minimumSize": 24, "currentSize": 24},
            "BTPluginExtensionRegistrationV1": {"minimumSize": 40, "currentSize": 40},
            "BTPluginHostV1": {"minimumSize": 24, "currentSize": 32},
            "BTPluginDescriptorV1": {"minimumSize": 40, "currentSize": 40},
        },
        "publicFileSHA256": hashes,
    }
    return (json.dumps(contract, indent=2, sort_keys=True) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-root", type=Path)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    sdk_root = (arguments.sdk_root or Path(__file__).resolve().parents[1]).resolve()
    rendered = render(sdk_root)
    contract_path = sdk_root / CONTRACT_PATH
    if arguments.check:
        try:
            existing = contract_path.read_bytes()
        except OSError as error:
            print(f"SDK contract is missing: {error}", file=sys.stderr)
            return 1
        if existing != rendered:
            print(
                "SDK contract drift detected; review compatibility, then intentionally regenerate SDKContractV1.json.",
                file=sys.stderr,
            )
            return 1
        print("SDK v1 generated-contract drift check passed.")
        return 0
    sys.stdout.buffer.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
