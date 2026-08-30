#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"
# This evidence runner will not boot or mutate a simulator; it only uses an
# explicitly booted device and removes its temporary fixture on exit.
battman_configure_developer_dir
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
OUTPUT_DIR="${1:-$REPO_ROOT/docs/evidence}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-plugin-management-evidence.XXXXXX")"
BUNDLE_ID="com.torrekie.Battman.PluginManagementEvidence"
APP_DIR="$TEST_TMP/PluginManagementEvidence.app"
CONTAINER_DIR=""
cleanup() {
	xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
	xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
	rm -rf "$TEST_TMP"
}
trap cleanup EXIT

CLANG="$(xcrun --sdk iphonesimulator --find clang)"
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
HOST_ARCH="${BATTMAN_SIMULATOR_ARCH:-$(uname -m)}"
case "$HOST_ARCH" in
	arm64) TARGET="arm64-apple-ios12.0-simulator" ;;
	x86_64) TARGET="x86_64-apple-ios12.0-simulator" ;;
	*) echo "Unsupported simulator host architecture: $HOST_ARCH" >&2; exit 1 ;;
esac

if [[ ! -d "$OUTPUT_DIR" ]]; then
	echo "The output directory must already exist: $OUTPUT_DIR" >&2
	exit 1
fi
mkdir -p "$APP_DIR"
cp "$REPO_ROOT/Tests/Simulator/PluginManagementEvidence-Info.plist" "$APP_DIR/Info.plist"
"$CLANG" \
	-target "$TARGET" \
	-isysroot "$SDKROOT" \
	-fobjc-arc -fblocks -fvisibility=hidden \
	-Wall -Wextra -Werror -Wno-deprecated-declarations \
	-DDEBUG=1 -DBATTMAN_VERSION_STRING=\"1.1.0\" \
	-I"$REPO_ROOT/Battman" \
	"$REPO_ROOT/Tests/Simulator/BTPluginManagementScreenshotHarness.m" \
	"$REPO_ROOT/Battman/PluginHost/UI/BTPluginManagementViewController.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Management/BTPluginManagementLineage.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginSource.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
	-o "$APP_DIR/PluginManagementEvidence"
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null
xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_UDID" "$APP_DIR"
CONTAINER_DIR="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null

STATUS_PATH="$CONTAINER_DIR/Documents/plugin-management-evidence.status"
for _ in $(seq 1 200); do
	[[ -f "$STATUS_PATH" ]] && break
	sleep 0.05
done
if [[ ! -f "$STATUS_PATH" ]] || [[ "$(cat "$STATUS_PATH")" != "PASS" ]]; then
	echo "The simulator app did not complete the evidence run." >&2
	exit 1
fi
cp "$CONTAINER_DIR"/Documents/plugin-1.1.0-management-*.png "$OUTPUT_DIR/"

python3 - "$OUTPUT_DIR" <<'PY'
import struct
import sys
from pathlib import Path

names = (
    "plugin-1.1.0-management-overview.png",
    "plugin-1.1.0-management-third-party-consent.png",
    "plugin-1.1.0-management-package-details.png",
    "plugin-1.1.0-management-technical-details.png",
    "plugin-1.1.0-management-exact-build-consent.png",
    "plugin-1.1.0-management-safe-mode.png",
    "plugin-1.1.0-management-diagnostics-disclosure.png",
)
root = Path(sys.argv[1])
for name in names:
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"missing regular screenshot: {name}")
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (780, 1688):
        raise SystemExit(f"unexpected PNG contract: {name}")
PY

echo "Plug-in management screenshot evidence passed."
