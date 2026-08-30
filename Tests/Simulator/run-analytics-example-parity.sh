#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"
battman_configure_developer_dir
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-analytics-example.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

CLANG="$(xcrun --sdk iphonesimulator --find clang)"
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
HOST_ARCH="${BATTMAN_SIMULATOR_ARCH:-$(uname -m)}"
case "$HOST_ARCH" in
	arm64) TARGET="arm64-apple-ios12.0-simulator" ;;
	x86_64) TARGET="x86_64-apple-ios12.0-simulator" ;;
	*) echo "Unsupported simulator host architecture: $HOST_ARCH" >&2; exit 1 ;;
esac
INCLUDES=(
	-I"$REPO_ROOT/PluginSDK/include"
	-I"$REPO_ROOT/PluginSDK/Examples/AnalyticsCard"
)
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
	"${INCLUDES[@]}"
)
FRAMEWORKS=(
	-framework Foundation
	-framework UIKit
	-framework QuartzCore
	-framework CoreGraphics
	-framework Security
)
HOST_SOURCES=(
	"$REPO_ROOT/Tests/Simulator/BTAnalyticsExampleParityHarness.m"
	"$REPO_ROOT/Battman/Features/Analytics/Public/BAAnalyticsMetricSnapshot.m"
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m"
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m"
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m"
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginNativeImageLoader.m"
)
EXAMPLE_SOURCE="$REPO_ROOT/PluginSDK/Examples/AnalyticsCard/BTAnalyticsExamplePlugin.m"
EXAMPLE_BUILD_VERSION="$(tr -d '\r\n' < \
	"$REPO_ROOT/PluginSDK/Examples/AnalyticsCard/BUILD_VERSION")"
COMMON_FLAGS+=("-DBT_ANALYTICS_EXAMPLE_PLUGIN_VERSION=\"$EXAMPLE_BUILD_VERSION\"")

mkdir -p "$TEST_TMP/BTAnalyticsExample.bundle"
cp "$REPO_ROOT/PluginSDK/Examples/AnalyticsCard/Info.plist" \
	"$TEST_TMP/BTAnalyticsExample.bundle/Info.plist"
"$CLANG" "${COMMON_FLAGS[@]}" -bundle -Wl,-dead_strip \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
	"$EXAMPLE_SOURCE" "${FRAMEWORKS[@]}" \
	-o "$TEST_TMP/BTAnalyticsExample.bundle/BTAnalyticsExample"
codesign --force --sign - --identifier com.torrekie.battman.example.analytics \
	"$TEST_TMP/BTAnalyticsExample.bundle" >/dev/null

"$CLANG" "${COMMON_FLAGS[@]}" -DBT_ANALYTICS_EXAMPLE_EMBEDDED=1 -DBT_PLUGIN_EMBEDDED=1 \
	"${HOST_SOURCES[@]}" "$EXAMPLE_SOURCE" "${FRAMEWORKS[@]}" \
	-o "$TEST_TMP/embedded-harness"
"$CLANG" "${COMMON_FLAGS[@]}" -DBT_ANALYTICS_EXAMPLE_EMBEDDED=0 \
	"${HOST_SOURCES[@]}" "${FRAMEWORKS[@]}" \
	-o "$TEST_TMP/bundle-harness"
codesign --force --sign - "$TEST_TMP/embedded-harness" >/dev/null
codesign --force --sign - "$TEST_TMP/bundle-harness" >/dev/null

EXPORTED_SYMBOLS="$(nm -gjU "$TEST_TMP/BTAnalyticsExample.bundle/BTAnalyticsExample")"
if [[ "$EXPORTED_SYMBOLS" != '_BattmanPluginEntryPointV1' ]]; then
	echo "The example bundle exported an unexpected public symbol set:" >&2
	printf '%s\n' "$EXPORTED_SYMBOLS" >&2
	exit 1
fi
if otool -L "$TEST_TMP/BTAnalyticsExample.bundle/BTAnalyticsExample" | tail -n +2 | \
	grep -Ev '^\s+(/System/Library/Frameworks/|/usr/lib/)' | grep -q .; then
	echo "The example bundle links a non-system dependency." >&2
	exit 1
fi

EMBEDDED_RESULT="$(xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_TMP/embedded-harness")"
BUNDLE_RESULT="$(xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_TMP/bundle-harness" \
	"$TEST_TMP/BTAnalyticsExample.bundle/BTAnalyticsExample")"
if [[ "$EMBEDDED_RESULT" != "$BUNDLE_RESULT" ]]; then
	echo "Embedded and native Analytics example results differ." >&2
	diff -u <(printf '%s\n' "$EMBEDDED_RESULT") <(printf '%s\n' "$BUNDLE_RESULT") >&2 || true
	exit 1
fi

printf '%s\n' "$EMBEDDED_RESULT"
echo "Analytics SDK example embedded/bundle registration, lifecycle, and pixel parity passed."
