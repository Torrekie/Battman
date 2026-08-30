#!/bin/bash

# Shared, non-mutating environment selection for opt-in Simulator runners.

battman_configure_developer_dir() {
	local developer_root
	if [[ -n "${DEVELOPER_DIR:-}" ]]; then
		developer_root="$DEVELOPER_DIR"
	elif ! developer_root="$(xcode-select -p 2>/dev/null)"; then
		echo "No active Xcode developer directory. Set DEVELOPER_DIR or select Xcode with xcode-select." >&2
		return 1
	fi

	if [[ ! -d "$developer_root" ]]; then
		echo "The selected Xcode developer directory does not exist: $developer_root" >&2
		return 1
	fi

	DEVELOPER_DIR="$developer_root"
	export DEVELOPER_DIR
}

battman_select_booted_iphone_simulator() {
	local requested="${BATTMAN_SIMULATOR_UDID:-}"
	local selection

	if ! selection="$(
		xcrun simctl list devices available --json |
			BATTMAN_REQUESTED_SIMULATOR_UDID="$requested" python3 -c '
import json
import os
import sys

requested = os.environ.get("BATTMAN_REQUESTED_SIMULATOR_UDID", "")
devices = json.load(sys.stdin).get("devices", {})
candidates = []
for runtime, entries in devices.items():
    if ".SimRuntime.iOS-" not in runtime:
        continue
    for item in entries:
        if not item.get("isAvailable", True):
            continue
        identifier = item.get("deviceTypeIdentifier", "")
        name = item.get("name", "")
        if ".iPhone-" not in identifier and not name.startswith("iPhone"):
            continue
        candidates.append((runtime, name, item.get("udid", ""), item.get("state", "Unknown")))

if requested:
    matches = [item for item in candidates if item[2].casefold() == requested.casefold()]
    if not matches:
        raise SystemExit(
            "BATTMAN_SIMULATOR_UDID does not identify an available iPhone simulator: "
            + requested
        )
    selected = matches[0]
    if selected[3] != "Booted":
        raise SystemExit(
            "The requested simulator is not Booted: "
            + selected[2]
            + ". Boot it explicitly before running this harness."
        )
else:
    booted = sorted(item for item in candidates if item[3] == "Booted")
    if not booted:
        raise SystemExit(
            "No compatible Booted iPhone simulator is available. Set "
            "BATTMAN_SIMULATOR_UDID to one you booted explicitly; this harness "
            "will not create or boot a simulator."
        )
    selected = booted[0]

print(selected[2])
'
	)"; then
		return 1
	fi

	printf '%s\n' "$selection"
}
