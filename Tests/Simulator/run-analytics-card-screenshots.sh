#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 EXISTING_FRESH_OUTPUT_DIRECTORY" >&2
	exit 2
fi

OUTPUT_DIR="$1"
if [[ ! -d "$OUTPUT_DIR" ]]; then
	echo "The output directory must already exist: $OUTPUT_DIR" >&2
	exit 1
fi

SCREENSHOTS=(
	analytics-cards-synthetic-iphone-light.png
	analytics-cards-synthetic-iphone-dark.png
	analytics-cards-synthetic-wide-rtl-edit.png
)
for screenshot in "${SCREENSHOTS[@]}"; do
	path="$OUTPUT_DIR/$screenshot"
	if [[ -e "$path" || -L "$path" ]]; then
		echo "Refusing to replace an existing output: $path" >&2
		exit 1
	fi
done

battman_configure_developer_dir

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-analytics-card-screenshots.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

CLANG="$(xcrun --sdk iphonesimulator --find clang)"
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
HOST_ARCH="${BATTMAN_SIMULATOR_ARCH:-$(uname -m)}"
case "$HOST_ARCH" in
	arm64) TARGET="arm64-apple-ios12.0-simulator" ;;
	x86_64) TARGET="x86_64-apple-ios12.0-simulator" ;;
	*) echo "Unsupported simulator host architecture: $HOST_ARCH" >&2; exit 1 ;;
esac

COMMON_FLAGS=(
	-target "$TARGET"
	-isysroot "$SDKROOT"
	-fobjc-arc
	-fblocks
	-fvisibility=hidden
	-Wall
	-Wextra
	-Werror
	-Wno-deprecated-declarations
	-I"$REPO_ROOT/Battman"
	-I"$REPO_ROOT/PluginSDK/include"
)
SOURCES=(
	"$REPO_ROOT/Tests/Simulator/BTAnalyticsCardsScreenshotHarness.m"
	"$REPO_ROOT/Battman/Features/Analytics/Public/BAAnalyticsMetricSnapshot.m"
	"$REPO_ROOT/Battman/Features/Analytics/Host/AnalyticsCardCell.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCards.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsBatterySummaryCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsTemperatureAverageCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsPowerAverageCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsCycleSummaryCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsRemainingCapacityCard.m"
	"$REPO_ROOT/Battman/Features/Analytics/BuiltIn/BAAnalyticsChargingLimitCard.m"
	"$REPO_ROOT/Battman/ObjCExt/CALayer+smoothCorners.m"
	"$REPO_ROOT/Battman/ObjCExt/UIColor+compat.m"
	"$REPO_ROOT/Battman/ObjCExt/UIScreen+Auto.m"
)
FRAMEWORKS=(
	-framework Foundation
	-framework UIKit
	-framework QuartzCore
	-framework CoreGraphics
)

"$CLANG" "${COMMON_FLAGS[@]}" -DDEBUG=1 -DBATTMAN_VERSION_STRING=\"1.1.0\" \
	"${SOURCES[@]}" "${FRAMEWORKS[@]}" \
	-o "$TEST_TMP/analytics-card-screenshots"
codesign --force --sign - --timestamp=none "$TEST_TMP/analytics-card-screenshots" >/dev/null
echo "Analytics card screenshot harness compiled successfully."

# Compilation intentionally precedes Simulator selection so the focused build
# remains useful when no caller-booted iPhone is currently available.
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
xcrun simctl spawn "$SIMULATOR_UDID" \
	"$TEST_TMP/analytics-card-screenshots" "$OUTPUT_DIR"

python3 - "$OUTPUT_DIR" <<'PY'
import struct
import sys
from pathlib import Path

expected = {
    "analytics-cards-synthetic-iphone-light.png": (390, 844),
    "analytics-cards-synthetic-iphone-dark.png": (390, 844),
    "analytics-cards-synthetic-wide-rtl-edit.png": (1024, 660),
}
root = Path(sys.argv[1])
for name, size in expected.items():
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"missing regular screenshot: {name}")
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != size:
        raise SystemExit(f"unexpected PNG contract: {name}")
PY

echo "Analytics card screenshots passed: six production cards, synthetic fixtures only."
