#!/bin/bash

set -euo pipefail

export PYTHONDONTWRITEBYTECODE=1

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-sdk-clean-room.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

cp -R "$REPO_ROOT/PluginSDK" "$TEST_TMP/PluginSDK"
SDK_COPY="$TEST_TMP/PluginSDK"
if rg -n '/Users/[A-Za-z0-9._-]+|Battman/PluginHost|Battman/Features' "$SDK_COPY"; then
	echo "copied SDK contains a host-private or checkout-specific reference" >&2
	exit 1
fi

export DEVELOPER_DIR="$DEVELOPER_ROOT"
python3 "$SDK_COPY/Tools/generate-sdk-contract.py" --check

# Use a conspicuous valid build version in the disposable copy so the native
# binaries prove that both SDK build modes consume BUILD_VERSION rather than a
# coincidentally matching source literal.
TEST_BUILD_VERSION=3141592653
printf '%s\n' "$TEST_BUILD_VERSION" > \
	"$SDK_COPY/Examples/AnalyticsCard/BUILD_VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TEST_BUILD_VERSION" \
	"$SDK_COPY/Examples/AnalyticsCard/Info.plist"
python3 - "$SDK_COPY/Examples/AnalyticsCard/ManifestTemplate.json.in" \
	"$TEST_BUILD_VERSION" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["buildVersion"] = sys.argv[2]
path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
PY
make -C "$SDK_COPY" BUILD_DIR="$TEST_TMP/example-build" -j1 example >/dev/null
for artifact in \
	"$TEST_TMP/example-build/BTAnalyticsExample.bundle/BTAnalyticsExample" \
	"$TEST_TMP/example-build/BTAnalyticsExample.embedded.o"; do
	if ! strings "$artifact" | grep -Fqx "$TEST_BUILD_VERSION"; then
		echo "SDK example artifact did not bind its descriptor to BUILD_VERSION: $artifact" >&2
		exit 1
	fi
done
python3 "$REPO_ROOT/Tests/PluginSDK/test_clean_room_package.py" \
	"$SDK_COPY" "$TEST_TMP/example-build/BTAnalyticsExample.bundle" "$TEST_TMP"
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
COMMON=(
	-target arm64-apple-ios12.0
	-isysroot "$SDKROOT"
	-Wall -Wextra -Werror
	-I"$SDK_COPY/include"
)
"$CLANG" "${COMMON[@]}" -std=c11 -c "$SDK_COPY/TestSupport/Compile/ABIConsumer.c" \
	-o "$TEST_TMP/abi-c.o"
"$CLANG" "${COMMON[@]}" -x c++ -std=c++17 -c "$SDK_COPY/TestSupport/Compile/ABIConsumer.cc" \
	-o "$TEST_TMP/abi-cxx.o"
"$CLANG" "${COMMON[@]}" -fobjc-arc -fblocks -c \
	"$SDK_COPY/TestSupport/Compile/PublicHeaders.m" -o "$TEST_TMP/public-objc.o"
"$CLANG" "${COMMON[@]}" -fobjc-arc -fblocks -x objective-c++ -std=c++17 -c \
	"$SDK_COPY/TestSupport/Compile/PublicHeaders.mm" -o "$TEST_TMP/public-objcxx.o"

GENERATED="$TEST_TMP/ThirdPartyCard"
python3 "$SDK_COPY/Tools/create-analytics-card.py" \
	--plugin-id com.example.battman.clean-room \
	--card-id com.example.battman.clean-room.charge \
	--display-name 'Clean Room Charge' \
	--author-name 'Clean Room Developer' \
	--homepage-url 'https://example.com/clean-room' \
	--support-email 'support@example.com' \
	--output "$GENERATED" >/dev/null
make -C "$GENERATED" SDK_ROOT="$SDK_COPY" BUILD_DIR="$TEST_TMP/generated-build" \
	DEVELOPER_DIR="$DEVELOPER_ROOT" -j1 all >/dev/null
if [[ "$(tr -d '\r\n' < "$GENERATED/BUILD_VERSION")" != "$TEST_BUILD_VERSION" ]] || \
	! strings "$TEST_TMP/generated-build/BTAnalyticsExample.bundle/BTAnalyticsExample" | \
	grep -Fqx "$TEST_BUILD_VERSION"; then
	echo "generated Analytics card did not retain its canonical build version" >&2
	exit 1
fi
MANIFEST_TEMPLATE="$TEST_TMP/ManifestTemplate.json"
python3 "$SDK_COPY/Tools/render-example-manifest.py" \
	--template "$GENERATED/ManifestTemplate.json.in" \
	--publisher-key-id 1111111111111111111111111111111111111111111111111111111111111111 \
	--output "$MANIFEST_TEMPLATE"
python3 -c 'import json,sys; value=json.load(open(sys.argv[1])); assert value["pluginIdentifier"] == "com.example.battman.clean-room"; assert value["buildVersion"] == sys.argv[2]; assert value["author"] == {"name": "Clean Room Developer", "homepageURL": "https://example.com/clean-room", "supportEmail": "support@example.com"}; assert "files" not in value' "$MANIFEST_TEMPLATE" "$TEST_BUILD_VERSION"

INVALID_GENERATED="$TEST_TMP/InvalidAuthorCard"
if python3 "$SDK_COPY/Tools/create-analytics-card.py" \
	--plugin-id com.example.battman.invalid-author \
	--card-id com.example.battman.invalid-author.card \
	--display-name 'Invalid Author Card' \
	--author-name 'Impersonator' \
	--homepage-url 'http://example.com' \
	--output "$INVALID_GENERATED" >/dev/null 2>&1; then
	echo "generated-card tool accepted a non-HTTPS author homepage" >&2
	exit 1
fi
if [[ -e "$INVALID_GENERATED" ]]; then
	echo "rejected author metadata left a partial generated project" >&2
	exit 1
fi

if find "$SDK_COPY" -type f \( -name '*.o' -o -name '*.bundle' \) -print | grep -q .; then
	echo "clean-room build wrote products into the copied SDK source tree" >&2
	exit 1
fi
echo "Public SDK clean-room C/C++/Objective-C/Objective-C++ and generated-card builds passed."
