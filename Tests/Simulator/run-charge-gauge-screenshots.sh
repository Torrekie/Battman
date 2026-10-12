#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"
battman_configure_developer_dir
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
OUTPUT_DIR="${1:-$REPO_ROOT/docs/evidence}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-charge-gauge-evidence.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT
TEST_APP="$TEST_TMP/ChargeGaugeEvidence.app"
mkdir -p "$TEST_APP"
cat > "$TEST_APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChargeGaugeEvidence</string>
<key>CFBundleIdentifier</key><string>com.torrekie.battman.tests.charge-gauge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
cp -R "$REPO_ROOT/OfficialPlugins/ChargeGauge/Resources/"*.lproj "$TEST_APP/"

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
	-I"$REPO_ROOT/OfficialPlugins/ChargeGauge"
)
SOURCES=(
	"$REPO_ROOT/Tests/Simulator/BTChargeGaugeScreenshotHarness.m"
	"$REPO_ROOT/Battman/Features/Analytics/Public/BAAnalyticsMetricSnapshot.m"
	"$REPO_ROOT/Battman/Features/Analytics/Host/AnalyticsCardCell.m"
	"$REPO_ROOT/Battman/ObjCExt/CALayer+smoothCorners.m"
	"$REPO_ROOT/Battman/ObjCExt/UIColor+compat.m"
	"$REPO_ROOT/Battman/ObjCExt/UIScreen+Auto.m"
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m"
)
FRAMEWORKS=(
	-framework Foundation
	-framework UIKit
	-framework QuartzCore
	-framework CoreGraphics
	-framework Security
)

BUILD_VERSION="$(tr -d '\r\n' < "$REPO_ROOT/OfficialPlugins/ChargeGauge/BUILD_VERSION")"
COMMON_FLAGS+=("-DBT_CHARGE_GAUGE_PLUGIN_VERSION=\"$BUILD_VERSION\"")
"$CLANG" "${COMMON_FLAGS[@]}" -DDEBUG=1 -DBATTMAN_VERSION_STRING=\"1.1.0\" \
	-DBT_PLUGIN_EMBEDDED=1 -DBT_CHARGE_GAUGE_NATIVE_TEST=0 \
	"${SOURCES[@]}" "$REPO_ROOT/OfficialPlugins/ChargeGauge/BTChargeGaugePlugin.m" \
	"${FRAMEWORKS[@]}" -o "$TEST_APP/ChargeGaugeEvidence"
codesign --force --sign - --timestamp=none "$TEST_APP" >/dev/null
xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_APP/ChargeGaugeEvidence" "$OUTPUT_DIR"

# Test the developer-facing bundle target and actual dlopen/entry-point path.
# The temporary bundle is never copied into a release or installed application.
make -s -C "$REPO_ROOT/OfficialPlugins/ChargeGauge" bundle SDK=iphonesimulator \
	TARGET="$TARGET" BUILD_DIR="$TEST_TMP/native" DEVELOPER_DIR="$DEVELOPER_DIR"
# Do not let host resources mask the loose native-image fixture's fallback.
rm -rf "$TEST_APP/"*.lproj
"$CLANG" "${COMMON_FLAGS[@]}" -DDEBUG=1 -DBATTMAN_VERSION_STRING=\"1.1.0\" \
	-DBT_CHARGE_GAUGE_NATIVE_TEST=1 "${SOURCES[@]}" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginNativeImageLoader.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"${FRAMEWORKS[@]}" -o "$TEST_APP/ChargeGaugeEvidence"
codesign --force --sign - --timestamp=none "$TEST_APP" >/dev/null
mkdir "$TEST_TMP/native-rendering"
xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_APP/ChargeGaugeEvidence" "$TEST_TMP/native-rendering" \
	"$TEST_TMP/native/BattmanChargeGauge.bundle/BattmanChargeGauge"

for screenshot in \
	plugin-1.1.0-charge-gauge-charging-2x1.png \
	plugin-1.1.0-charge-gauge-paused-1x1.png \
	plugin-1.1.0-charge-gauge-unavailable-1x1.png; do
	path="$OUTPUT_DIR/$screenshot"
	test -s "$path"
	file "$path" | grep -q 'PNG image data'
	cmp "$path" "$TEST_TMP/native-rendering/$screenshot"
done

python3 - "$OUTPUT_DIR" <<'PY'
import struct
import sys
from pathlib import Path

expected = {
    "plugin-1.1.0-charge-gauge-charging-2x1.png": (416, 228),
    "plugin-1.1.0-charge-gauge-paused-1x1.png": (228, 228),
    "plugin-1.1.0-charge-gauge-unavailable-1x1.png": (228, 228),
}
root = Path(sys.argv[1])
for name, size in expected.items():
    data = (root / name).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != size:
        raise SystemExit(f"unexpected PNG contract: {name}")
PY

echo "Charge Gauge embedded/native rendering parity and embedded localization passed."
