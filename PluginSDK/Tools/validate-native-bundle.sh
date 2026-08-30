#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
	echo "usage: validate-native-bundle.sh BUNDLE PLUGIN_IDENTIFIER ENTRY_POINT" >&2
	exit 64
fi

BUNDLE=$1
PLUGIN_IDENTIFIER=$2
ENTRY_POINT=$3

if [ ! -d "$BUNDLE" ] || [ -L "$BUNDLE" ]; then
	echo "bundle must be a non-symlink directory: $BUNDLE" >&2
	exit 2
fi
INFO_PLIST="$BUNDLE/Info.plist"
if [ ! -f "$INFO_PLIST" ] || [ -L "$INFO_PLIST" ]; then
	echo "bundle Info.plist is missing or unsafe" >&2
	exit 2
fi
plutil -lint "$INFO_PLIST" >/dev/null
ACTUAL_IDENTIFIER=$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")
EXECUTABLE_NAME=$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")
if [ "$ACTUAL_IDENTIFIER" != "$PLUGIN_IDENTIFIER" ]; then
	echo "bundle identifier mismatch: $ACTUAL_IDENTIFIER" >&2
	exit 2
fi
case "$EXECUTABLE_NAME" in
	""|*/*|*\\*|.|..) echo "unsafe CFBundleExecutable" >&2; exit 2 ;;
esac
EXECUTABLE="$BUNDLE/$EXECUTABLE_NAME"
if [ ! -f "$EXECUTABLE" ] || [ -L "$EXECUTABLE" ]; then
	echo "bundle executable is missing or unsafe" >&2
	exit 2
fi

EXPORTED=$(nm -gjU "$EXECUTABLE")
if [ "$EXPORTED" != "_$ENTRY_POINT" ]; then
	echo "unexpected public symbol set:" >&2
	printf '%s\n' "$EXPORTED" >&2
	exit 2
fi

DEPENDENCIES=$(otool -L "$EXECUTABLE" | tail -n +2 | sed 's/^[[:space:]]*//; s/ (compatibility.*$//')
while IFS= read -r DEPENDENCY; do
	[ -z "$DEPENDENCY" ] && continue
	case "$DEPENDENCY" in
		/System/Library/Frameworks/*|/usr/lib/*) ;;
		*) echo "non-system dependency: $DEPENDENCY" >&2; exit 2 ;;
	esac
done <<EOF
$DEPENDENCIES
EOF

codesign --verify --strict "$BUNDLE"
echo "Native SDK bundle surface passed: one entry point and Apple system dependencies only."
