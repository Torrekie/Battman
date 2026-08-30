#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"
battman_configure_developer_dir
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-plugin-application-integration.XXXXXX")"
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
)
SOURCES=(
	"$REPO_ROOT/Tests/Simulator/BTPluginApplicationIntegrationHarness.m"
	"$REPO_ROOT/Battman/PluginHost/Application/BTPluginApplicationIntegration.m"
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m"
)
FRAMEWORKS=(
	-framework Foundation
	-framework UIKit
)

"$CLANG" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" "${FRAMEWORKS[@]}" \
	-o "$TEST_TMP/plugin-application-integration"
codesign --force --sign - --timestamp=none "$TEST_TMP/plugin-application-integration" >/dev/null

xcrun simctl spawn "$SIMULATOR_UDID" "$TEST_TMP/plugin-application-integration"
