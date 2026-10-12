#!/bin/sh

set -eu

ANALYTICS_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ANALYTICS_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/battman-history-tests.XXXXXX")
trap 'rm -rf "$ANALYTICS_TEST_TMP"' EXIT HUP INT TERM

ANALYTICS_CLANG=$(xcrun --sdk macosx --find clang)
ANALYTICS_MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path)

"$ANALYTICS_CLANG" \
	-isysroot "$ANALYTICS_MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -lsqlite3 \
	"$ANALYTICS_REPO_ROOT/Tests/Analytics/BAAnalyticsHistoryTests.m" \
	"$ANALYTICS_REPO_ROOT/Battman/Features/Analytics/Data/BAAnalyticsHistoryModels.m" \
	"$ANALYTICS_REPO_ROOT/Battman/Features/Analytics/Data/BAAnalyticsReport.m" \
	"$ANALYTICS_REPO_ROOT/Battman/Features/Analytics/Data/BAAnalyticsHistoryReader.m" \
	"$ANALYTICS_REPO_ROOT/Battman/Features/Analytics/Data/BAAnalyticsHistoryService.m" \
	-o "$ANALYTICS_TEST_TMP/history-tests"
"$ANALYTICS_TEST_TMP/history-tests"
