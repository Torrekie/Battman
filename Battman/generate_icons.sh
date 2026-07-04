#!/bin/sh
#
# Usage: ./convert_all_icons.sh icon.svg [destination_dir]
#
# This script converts an SVG into icon PNGs for both pre‑iOS7 and post‑iOS7.
#
# It uses two hard‑coded lists:
#
# (A) Pre‑iOS7 icons – a minimal set required for older iOS.
# (B) Post‑iOS7 icons – an extended set for newer devices and App Store:
#
#     • 180.png    180×180   (iPhone 60pt @3x)
#     • 120.png    120×120   (iPhone 60pt @2x or 40pt @3x; both entries merge)
#     • 80.png      80×80    (iPhone 40pt @2x / iPad 40pt @2x)
#     • 57.png     57×57     (iPhone 57pt @1x)
#     • 29.png     29×29     (iPhone 29pt @1x)
#     • 58.png     58×58     (iPhone 29pt @2x)
#     • 87.png     87×87     (iPhone 29pt @3x)
#     • 114.png   114×114     (iPhone 57pt @2x)
#     • 40.png     40×40     (iPhone 20pt @2x / iPad 20pt @2x)
#     • 60.png     60×60     (iPhone 20pt @3x)
#     • 1024.png 1024×1024   (App Store)
#
#     • 152.png   152×152   (iPad 76pt @2x)
#     • 100.png   100×100   (iPad 50pt @2x)
#     • 144.png   144×144   (iPad 72pt @2x)
#     • 167.png   167×167   (iPad 83.5pt @2x)
#
#     • 128.png   128×128   (Mac)
#     • 256.png   256×256   (Mac)
#     • 512.png   512×512   (Mac)
#     • 32.png     32×32    (Mac)
#     • 16.png     16×16    (Mac)
#     • 64.png     64×64    (Mac)
#
# The script then outputs two plist snippets:
#
#   1. A CFBundleIconFiles (pre‑iOS7) array – simply listing the base names
#      (without the “.png” extension) of the pre‑iOS7 icons.
#
#   2. A CFBundleIcons dictionary for post‑iOS7 – under CFBundlePrimaryIcon,
#      listing all unique post‑iOS7 icon base names.
#
# Requirements: qlmanage or sips on macOS, or inkscape, rsvg-convert, or convert.
#
SVG="$1"
OUTDIR="$2"

if [ -z "$SVG" ]; then
  echo "Usage: $0 icon.svg [destination_dir]"
  exit 1
fi

# Use current directory if no destination specified.
[ -z "$OUTDIR" ] && OUTDIR="."
mkdir -p "$OUTDIR"

# ----------------------------------------------------------------
# Determine available conversion tool and define a helper function.
# Usage: convert_cmd width height input.svg output.png
if command -v qlmanage >/dev/null 2>&1; then
    CONVERTER="qlmanage"
    convert_cmd() {
      tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/battman-icons.XXXXXX")" || return 1
      if qlmanage -t -s "$1" -o "$tmpdir" "$3" >/dev/null 2>&1; then
        tmpout="$tmpdir/$(basename "$3").png"
        if [ -f "$tmpout" ]; then
          mv "$tmpout" "$4"
          rmdir "$tmpdir" 2>/dev/null || true
          return 0
        fi
      fi
      rm -rf "$tmpdir"
      return 1
    }
elif command -v sips >/dev/null 2>&1; then
    CONVERTER="sips"
    convert_cmd() {
      sips -s format png -z "$2" "$1" "$3" --out "$4" >/dev/null
    }
elif command -v inkscape >/dev/null 2>&1; then
    # The reason we put inkscape first is because Battman.svg is made with inkscape
    CONVERTER="inkscape"
    convert_cmd() {
      # Inkscape 1.x style export command.
      inkscape "$3" --export-width="$1" --export-height="$2" --export-filename="$4"
    }
elif command -v convert >/dev/null 2>&1; then
    CONVERTER="convert (ImageMagick)"
    convert_cmd() {
      # Force exact dimensions using "!" and preserve transparency.
      convert "$3" -resize "${1}x${2}!" "$4"
    }
elif command -v rsvg-convert >/dev/null 2>&1; then
    CONVERTER="rsvg-convert"
    convert_cmd() {
      rsvg-convert -w "$1" -h "$2" "$3" -o "$4"
    }
else
    echo "Error: No suitable SVG conversion tool found (requires inkscape, convert or rsvg-convert)." >&2
    exit 1
fi

echo "Using conversion tool: $CONVERTER"

# ----------------------------------------------------------------
# (A) Pre‑iOS7 icon definitions
# https://developer.apple.com/library/archive/qa/qa1686/_index.html
#   Format: filename width

PRE_ICONS="
Icon-60.png 60
Icon-60@2x.png 120
Icon-60@3x.png 180
Icon-72.png 72
Icon-72@2x.png 144
Icon-76@2x~ipad.png 152
Icon-76~ipad.png 76
Icon-83.5@2x.png 167
Icon-Small-40.png 40
Icon-Small-40@2x.png 80
Icon-Small-40@3x.png 120
Icon-Small-50.png 50
Icon-Small-50@2x.png 100
Icon-Small.png 29
Icon-Small@2x.png 58
Icon-Small@3x.png 87
Icon.png 57
Icon@2x.png 114
"

# ----------------------------------------------------------------
# (B) Post‑iOS7 icon definitions (extended set)
POST_ICONS="
180.png 180
120.png 120
80.png 80
57.png 57
29.png 29
58.png 58
87.png 87
114.png 114
40.png 40
60.png 60
1024.png 1024
152.png 152
100.png 100
144.png 144
167.png 167
128.png 128
256.png 256
512.png 512
32.png 32
16.png 16
64.png 64
"

# It seems we don't need too much icon sets, iOS auto resizes for us
LARGE_ICON="
1024.png 1024
"

# Combine both lists uniquely.
#ALL_ICONS=$(echo "$PRE_ICONS
#$POST_ICONS" | awk '!a[$1]++')
ALL_ICONS=$(echo "$LARGE_ICON" | awk '!a[$1]++')

# ----------------------------------------------------------------
# Convert SVG to PNG using the selected tool.
echo "Generating icons from $SVG ..."
echo "$ALL_ICONS" | while read -r NAME WIDTH; do
  [ -z "$NAME" ] && continue
  OUTPUT="$OUTDIR/$NAME"
  [ -e "$OUTPUT" ] && continue
  echo "  Generating $OUTPUT (${WIDTH}×${WIDTH})..."
  convert_cmd "$WIDTH" "$WIDTH" "$SVG" "$OUTPUT"
done

# ----------------------------------------------------------------
# Output the plist snippet for pre‑iOS7 apps.
#echo
#echo "Pre‑iOS7 CFBundleIconFiles entry (add to your Info.plist):"
#echo "<key>CFBundleIconFiles</key>"
#echo "<array>"
#for icon in Icon Icon-72 Icon-60 Icon-76 Icon-Small-40 Icon-Small Icon-Small-50 Icon-83.5; do
#  echo "    <string>$icon</string>"
#done
#echo "</array>"

# ----------------------------------------------------------------
# Output the plist snippet for iOS 7+ (post‑iOS7).
echo
echo "Post‑iOS7 CFBundleIcons entry (add to your Info.plist):"
echo "<key>CFBundleIcons</key>"
echo "<dict>"
echo "    <key>CFBundlePrimaryIcon</key>"
echo "    <dict>"
echo "        <key>CFBundleIconFiles</key>"
echo "        <array>"
# List the unique post‑iOS7 icon filenames (strip the '.png') and sort them.
for icon in $(echo "$LARGE_ICON" | awk '{print $1}' | sed 's/\.png$//' | sort -u); do
  echo "            <string>$icon</string>"
done
echo "        </array>"
echo "        <key>UIPrerenderedIcon</key>"
echo "        <false/>"
echo "    </dict>"
echo "</dict>"
