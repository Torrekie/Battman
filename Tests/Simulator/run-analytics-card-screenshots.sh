#!/bin/bash
# Serial, opt-in UIKit run against one caller-booted iPhone. No real sensors.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_ROOT/Tests/Simulator/simulator-runner-common.sh"
[[ $# -eq 1 && -d "$1" ]] || { echo 'Usage: runner EXISTING_FRESH_OUTPUT_DIRECTORY' >&2; exit 2; }
OUTPUT_DIR="$1"
[[ ! -e "$OUTPUT_DIR/validation.json" ]] || { echo 'Refusing to replace evidence' >&2; exit 1; }
battman_configure_developer_dir
SIMULATOR_UDID="$(battman_select_booted_iphone_simulator)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/battman-analytics-v3.XXXXXX")"
BUNDLE_ID="com.torrekie.Battman.AnalyticsV3Fixture.$(uuidgen | tr -d '-')"
APP_DIR="$TEST_TMP/AnalyticsV3Fixture.app"
INSTALLED=0
SUCCEEDED=0
cleanup() {
    if [[ "$INSTALLED" == 1 && ( "${BATTMAN_KEEP_FIXTURE:-0}" != 1 || "$SUCCEEDED" != 1 ) ]]; then
        xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT
EXISTING_APP="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" app 2>/dev/null || true)"
if [[ -n "$EXISTING_APP" && -d "$EXISTING_APP" ]]; then
    echo 'Fixture already installed; remove only your previous fixture before rerunning' >&2; exit 1
fi
mkdir -p "$APP_DIR"
python3 - "$APP_DIR/Info.plist" "$BUNDLE_ID" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:plistlib.dump({'CFBundleIdentifier':sys.argv[2],'CFBundleExecutable':'AnalyticsV3Fixture','CFBundleName':'AnalyticsV3Fixture','CFBundleDisplayName':'Analytics V3 Fixture','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1','LSRequiresIPhoneOS':True,'MinimumOSVersion':'12.0','UIDeviceFamily':[1],'CFBundleSupportedPlatforms':['iPhoneSimulator'],'UILaunchStoryboardName':'FixtureLaunch'},f,fmt=plistlib.FMT_XML)
PY
# Exact tracked gettext translations drive presentation QA; production still
# uses Battman's libintl-backed cond_localize implementation.
python3 - "$REPO_ROOT" "$APP_DIR/fixture-catalogs.json" <<'PY_CATALOG'
import importlib.util,json,sys
from pathlib import Path
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('coverage',root/'Tests/check-analytics-localizations.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
catalogs={name:module.parse_catalog(root/'Battman/Localizations'/f'{name}.po') for name in ['en','de','zh_CN','zh_TW']}
Path(sys.argv[2]).write_text(json.dumps(catalogs,ensure_ascii=False))
PY_CATALOG
CLANG="$(xcrun --sdk iphonesimulator --find clang)"
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="${BATTMAN_SIMULATOR_ARCH:-$(uname -m)}-apple-ios12.0-simulator"
SOURCES=("$REPO_ROOT/Tests/Simulator/BTAnalyticsCardsScreenshotHarness.m" "$REPO_ROOT/Tests/Simulator/BAAnalyticsV3Fixtures.m")
# Mirror production Analytics source membership except physical acquisition.
python3 - "$REPO_ROOT" > "$TEST_TMP/sources.txt" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);legacy={'BAAnalyticsBuiltInCard.m','BAAnalyticsBatterySummaryCard.m','BAAnalyticsTemperatureAverageCard.m','BAAnalyticsPowerAverageCard.m','BAAnalyticsCycleSummaryCard.m','BAAnalyticsRemainingCapacityCard.m','BAAnalyticsChargingLimitCard.m','BAAnalyticsSystemMetricSource.m'}
for p in sorted((root/'Battman/Features/Analytics').rglob('*.m')):
    if p.name not in legacy and 'Tests' not in p.parts:print(p.relative_to(root))
PY
while IFS= read -r path; do SOURCES+=("$REPO_ROOT/$path"); done < "$TEST_TMP/sources.txt"
for path in BTEmbeddedPluginRegistration BTPluginExtensionDescriptor BTPluginIdentifiers BTPluginRegistry; do SOURCES+=("$REPO_ROOT/Battman/PluginHost/$path.m"); done
SOURCES+=("$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m")
for path in CALayer+smoothCorners UIColor+compat UIScreen+Auto; do SOURCES+=("$REPO_ROOT/Battman/ObjCExt/$path.m"); done
"$CLANG" -target "$TARGET" -isysroot "$SDKROOT" -fobjc-arc -fblocks -fvisibility=hidden \
    -Wall -Wextra -Werror -Wno-deprecated-declarations -Wno-unused-parameter -Wno-sign-compare -Wno-incomplete-implementation \
    -DDEBUG=1 -DBATTMAN_SIMULATOR_UI_FIXTURE=1 -DBATTMAN_VERSION_STRING=\"1.1.0\" \
    -I"$REPO_ROOT/Battman" -I"$REPO_ROOT/PluginSDK/include" \
    "${SOURCES[@]}" -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -lsqlite3 -lz -o "$APP_DIR/AnalyticsV3Fixture"
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null
xcrun simctl install "$SIMULATOR_UDID" "$APP_DIR"
INSTALLED=1
CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data)"
touch "$TEST_TMP/fixture.stdout" "$TEST_TMP/fixture.stderr"
SIMCTL_CHILD_BATTMAN_ANALYTICS_PERFORMANCE_ONLY="${BATTMAN_ANALYTICS_PERFORMANCE_ONLY:-0}" \
SIMCTL_CHILD_BATTMAN_ANALYTICS_HISTORY_ONLY="${BATTMAN_ANALYTICS_HISTORY_ONLY:-0}" \
    xcrun simctl launch --stdout="$TEST_TMP/fixture.stdout" --stderr="$TEST_TMP/fixture.stderr" "$SIMULATOR_UDID" "$BUNDLE_ID"
STATUS_PATH="$CONTAINER/Documents/analytics-v3.status"
for _ in $(seq 1 600); do [[ -f "$STATUS_PATH" ]] && break; sleep 0.1; done
if [[ ! -f "$STATUS_PATH" ]]; then
    echo 'Fixture did not finish within 60 seconds' >&2
    tail -n 30 "$TEST_TMP/fixture.stderr" >&2 || true
    exit 1
fi
if [[ "$(cat "$STATUS_PATH")" != PASS ]]; then cat "$STATUS_PATH" >&2; exit 1; fi
python3 - "$OUTPUT_DIR/fixture.json" "$BUNDLE_ID" "$SIMULATOR_UDID" <<'PY'
import json,sys
with open(sys.argv[1],'w') as f:json.dump({'bundleID':sys.argv[2],'simulatorUDID':sys.argv[3]},f)
PY
cp "$CONTAINER/Documents/validation.json" "$OUTPUT_DIR/"
# Focused history checks produce no screenshots; performance mode captures
# a finite set of dense/cached canvases and changed process geometries.
shopt -s nullglob
SCREENSHOTS=("$CONTAINER"/Documents/*.png)
if (( ${#SCREENSHOTS[@]} )); then cp "${SCREENSHOTS[@]}" "$OUTPUT_DIR/"; fi
python3 - "$OUTPUT_DIR" <<'PY'
import json,struct,sys
from pathlib import Path
root=Path(sys.argv[1]);data=json.loads((root/'validation.json').read_text())
for item in data['renderings']:
    b=(root/item['image']).read_bytes()
    assert b[:8]==b'\x89PNG\r\n\x1a\n'
    w,h=struct.unpack('>II',b[16:24]);assert 100<=w<=430 and 100<=h<=430
print('PASS:',len(data['renderings']),'production canvas renderings;',len(data['checks']),'checks')
PY
SUCCEEDED=1
if [[ "${BATTMAN_KEEP_FIXTURE:-0}" == 1 ]]; then echo "Temporary fixture $BUNDLE_ID retained for manual interaction on $SIMULATOR_UDID"; fi
