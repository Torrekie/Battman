#!/bin/bash

set -euo pipefail
export LANG=C
export LC_ALL=C

usage() {
	cat <<'EOF'
Usage:
  run-analytics-rooted-preflight.sh --host user@host [options]

Options:
  --host user@host          Required SSH target.
  --host-key-alias alias    Verify an IP address using an existing SSH host key.
  --app path                App bundle to inspect (default: current Makefile build).
  -h, --help                Show this help.

This command is read-only. It cannot stage, sign, register, launch, replace, or
restore an app. Device installation remains a separate, explicitly authorized
operation.
EOF
}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

valid_ssh_name() {
	case "$1" in
		''|-*|*[!A-Za-z0-9_.@:\[\]-]*) return 1 ;;
		*) return 0 ;;
	esac
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SSH_TARGET=
HOST_KEY_ALIAS=
APP_BUNDLE="$REPO_ROOT/Battman/build/Payload/Battman.app"

while [ "$#" -gt 0 ]; do
	case "$1" in
		--host)
			[ "$#" -ge 2 ] || fail "--host requires a value"
			SSH_TARGET=$2
			shift 2
			;;
		--host-key-alias)
			[ "$#" -ge 2 ] || fail "--host-key-alias requires a value"
			HOST_KEY_ALIAS=$2
			shift 2
			;;
		--app)
			[ "$#" -ge 2 ] || fail "--app requires a value"
			APP_BUNDLE=$2
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unknown argument: $1"
			;;
	esac
done

[ -n "$SSH_TARGET" ] || {
	usage >&2
	exit 64
}
valid_ssh_name "$SSH_TARGET" || fail "unsafe SSH target syntax"
if [ -n "$HOST_KEY_ALIAS" ]; then
	valid_ssh_name "$HOST_KEY_ALIAS" || fail "unsafe host-key alias syntax"
fi

require_command file
require_command nm
require_command plutil
require_command shasum
require_command ssh
require_command vtool

[ -d "$APP_BUNDLE" ] || fail "app bundle does not exist: $APP_BUNDLE"
INFO_PLIST="$APP_BUNDLE/Info.plist"
[ -f "$INFO_PLIST" ] || fail "Info.plist is missing: $INFO_PLIST"

BUNDLE_IDENTIFIER=$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")
[ "$BUNDLE_IDENTIFIER" = "com.torrekie.Battman" ] || \
	fail "unexpected bundle identifier: $BUNDLE_IDENTIFIER"
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
EXECUTABLE_NAME=$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")
APP_EXECUTABLE="$APP_BUNDLE/$EXECUTABLE_NAME"
[ -f "$APP_EXECUTABLE" ] || fail "app executable is missing: $APP_EXECUTABLE"

FILE_DESCRIPTION=$(file "$APP_EXECUTABLE")
case "$FILE_DESCRIPTION" in
	*"Mach-O 64-bit executable arm64"*) ;;
	*) fail "app executable is not arm64 Mach-O: $FILE_DESCRIPTION" ;;
esac

MINIMUM_OS=$(vtool -show-build "$APP_EXECUTABLE" | awk '$1 == "minos" { print $2; exit }')
[ -n "$MINIMUM_OS" ] || fail "LC_BUILD_VERSION does not contain a minimum OS"
case "$MINIMUM_OS" in
	12|12.*) ;;
	*) fail "expected an iOS 12 minimum deployment target, got $MINIMUM_OS" ;;
esac

REQUIRED_SYMBOLS='BAAnalyticsBuiltInCard BAAnalyticsMetricService BAAnalyticsSystemMetricSource BTPluginRegistry'
EXPORTED_SYMBOLS=$(nm -gj "$APP_EXECUTABLE" 2>/dev/null || true)
for required_symbol in $REQUIRED_SYMBOLS; do
	grep -q "_OBJC_CLASS_.*${required_symbol}$" <<<"$EXPORTED_SYMBOLS" || \
		fail "required class is absent from the executable: $required_symbol"
done

UNSIGNED_SHA256=$(shasum -a 256 "$APP_EXECUTABLE" | awk '{ print $1 }')

SSH_OPTIONS=(
	-o BatchMode=yes
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o LogLevel=ERROR
	-o StrictHostKeyChecking=yes
)
if [ -n "$HOST_KEY_ALIAS" ]; then
	SSH_OPTIONS+=( -o "HostKeyAlias=$HOST_KEY_ALIAS" )
fi

REMOTE_REPORT=$(
	ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" /usr/bin/bash -s <<'REMOTE'
set -eu
export LANG=C
export LC_ALL=C
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

installed_app=/Applications/Battman.app
installed_binary=$installed_app/Battman

printf 'remote_uid=%s\n' "$(id -u)"
printf 'remote_hostname=%s\n' "$(hostname)"
printf 'remote_os_version=%s\n' "$(defaults read /System/Library/CoreServices/SystemVersion ProductVersion 2>/dev/null || true)"
printf 'remote_arch=%s\n' "$(uname -m)"
printf 'remote_dpkg_arch=%s\n' "$(dpkg --print-architecture 2>/dev/null || true)"
if [ -d /var/jb ]; then
	printf 'remote_rootless=yes\n'
else
	printf 'remote_rootless=no\n'
fi
printf 'remote_package_status=%s\n' "$(dpkg-query -W -f='${db:Status-Abbrev}' com.torrekie.battman 2>/dev/null || true)"
printf 'remote_package_version=%s\n' "$(dpkg-query -W -f='${Version}' com.torrekie.battman 2>/dev/null || true)"
printf 'remote_bundle_id=%s\n' "$(defaults read "$installed_app/Info" CFBundleIdentifier 2>/dev/null || true)"
printf 'remote_bundle_version=%s\n' "$(defaults read "$installed_app/Info" CFBundleShortVersionString 2>/dev/null || true)"
printf 'remote_binary_sha256=%s\n' "$(shasum -a 256 "$installed_binary" 2>/dev/null | awk '{ print $1 }')"
if command -v ldid >/dev/null 2>&1; then
	printf 'remote_ldid=yes\n'
	if ldid -e "$installed_binary" 2>/dev/null | grep -q '<key>com.apple.private.applesmc.user-access</key>'; then
		printf 'remote_applesmc_entitlement=yes\n'
	else
		printf 'remote_applesmc_entitlement=no\n'
	fi
else
	printf 'remote_ldid=no\n'
	printf 'remote_applesmc_entitlement=unknown\n'
fi
if command -v uicache >/dev/null 2>&1; then
	printf 'remote_uicache=yes\n'
else
	printf 'remote_uicache=no\n'
fi
if command -v uiopen >/dev/null 2>&1; then
	printf 'remote_uiopen=yes\n'
else
	printf 'remote_uiopen=no\n'
fi
printf 'remote_free_kib=%s\n' "$(df -k /Applications 2>/dev/null | awk 'END { print $4 }')"
printf 'remote_uptime=%s\n' "$(uptime)"
REMOTE
)

remote_value() {
	printf '%s\n' "$REMOTE_REPORT" | sed -n "s/^$1=//p"
}

[ "$(remote_value remote_uid)" = "0" ] || fail "SSH target is not running as root"
[ "$(remote_value remote_arch)" = "arm64" ] || fail "device architecture is not arm64"
[ "$(remote_value remote_dpkg_arch)" = "iphoneos-arm" ] || fail "device is not the rooted iphoneos-arm lane"
[ "$(remote_value remote_rootless)" = "no" ] || fail "device is rootless; use the rootless deployment lane"
[ "$(remote_value remote_package_status)" = "ii " ] || fail "Battman is not installed and configured through dpkg"
[ "$(remote_value remote_bundle_id)" = "com.torrekie.Battman" ] || fail "installed app has an unexpected bundle identifier"
[ "$(remote_value remote_ldid)" = "yes" ] || fail "ldid is unavailable on the device"
[ "$(remote_value remote_applesmc_entitlement)" = "yes" ] || fail "installed app lacks the AppleSMC entitlement"
[ "$(remote_value remote_uicache)" = "yes" ] || fail "uicache is unavailable on the device"
[ "$(remote_value remote_uiopen)" = "yes" ] || fail "uiopen is unavailable on the device"

REMOTE_OS_VERSION=$(remote_value remote_os_version)
REMOTE_OS_MAJOR=${REMOTE_OS_VERSION%%.*}
case "$REMOTE_OS_MAJOR" in
	''|*[!0-9]*) fail "could not determine the device OS version" ;;
	*) [ "$REMOTE_OS_MAJOR" -ge 12 ] || fail "device OS is older than iOS 12" ;;
esac

REMOTE_FREE_KIB=$(remote_value remote_free_kib)
case "$REMOTE_FREE_KIB" in
	''|*[!0-9]*) fail "could not determine free device storage" ;;
	*) [ "$REMOTE_FREE_KIB" -ge 65536 ] || fail "device has less than 64 MiB free" ;;
esac

printf 'local_bundle_id=%s\n' "$BUNDLE_IDENTIFIER"
printf 'local_version=%s\n' "$APP_VERSION"
printf 'local_minimum_os=%s\n' "$MINIMUM_OS"
printf 'local_unsigned_sha256=%s\n' "$UNSIGNED_SHA256"
printf '%s\n' "$REMOTE_REPORT"
printf '%s\n' 'preflight=passed'
printf '%s\n' 'remote_mutation=none'
