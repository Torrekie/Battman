#!/bin/bash
# Build only the pinned gettext runtime. All downloads and generated files stay
# in Xcode's build directories; no prebuilt library or local header is required.
set -euo pipefail

: "${PROJECT_DIR:?}"
: "${BUILD_DIR:?}"
: "${BUILT_PRODUCTS_DIR:?}"
: "${SDKROOT:?}"
: "${PLATFORM_NAME:?}"
: "${IPHONEOS_DEPLOYMENT_TARGET:?}"

version=0.23
digest=bf31a9b6bdf3e364669c7bd9858f97e4a0c408a8d22940c5d4ab638b65460f85
cache="$BUILD_DIR/BattmanDependencies/gettext-$version"
output="$BUILT_PRODUCTS_DIR/battman-gettext"
archive="$cache/gettext-$version.tar.xz"
source_dir="$cache/gettext-$version"
mkdir -p "$cache" "$output/include"

if [[ ! -f "$archive" ]]; then
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --retry 2 --max-time 120 "https://ftp.gnu.org/gnu/gettext/gettext-$version.tar.xz" \
        --output "$archive.download"
    printf '%s  %s\n' "$digest" "$archive.download" | shasum -a 256 --check --status
    mv "$archive.download" "$archive"
fi
printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 --check --status
if [[ ! -f "$source_dir/gettext-runtime/configure" ]]; then
    tar -xf "$archive" -C "$cache"
fi

case "$PLATFORM_NAME" in
    iphoneos) architectures=(arm64); target_suffix= ;;
    iphonesimulator) architectures=(arm64 x86_64); target_suffix=-simulator ;;
    *) echo 'error: gettext supports only the iOS device and simulator targets' >&2; exit 2 ;;
esac
compiler="$(xcrun --sdk "$PLATFORM_NAME" --find clang)"
recipe="$(shasum -a 256 "$PROJECT_DIR/Scripts/Build/build-gettext.sh" | cut -d ' ' -f 1)"
identity="$(printf '%s\n' "$recipe" "$SDKROOT" "$IPHONEOS_DEPLOYMENT_TARGET" \
    "$("$compiler" --version)" | shasum -a 256 | cut -d ' ' -f 1)"
libraries=()
for architecture in "${architectures[@]}"; do
    work="$cache/$PLATFORM_NAME-$architecture-$identity"
    mkdir -p "$work"
    if [[ ! -f "$work/complete" ]]; then
        target="$architecture-apple-ios$IPHONEOS_DEPLOYMENT_TARGET$target_suffix"
        case "$architecture" in arm64) host=aarch64-apple-darwin ;; *) host=x86_64-apple-darwin ;; esac
        (
            cd "$work"
            trap 'echo "error: gettext runtime failed; inspect $PWD/configure.log and build.log" >&2' ERR
            # Autoconf treats CC as words rather than a shell-quoted path. Keep
            # SDK and compiler paths in a wrapper so spaces remain intact.
            mkdir -p tools
            printf '#!/bin/bash\nexec %q -target %q -isysroot %q "$@"\n' \
                "$compiler" "$target" "$SDKROOT" > tools/battman-target-clang
            chmod 700 tools/battman-target-clang
            export PATH="$work/tools:$PATH"
            CC=battman-target-clang CFLAGS=-Os \
                "$source_dir/gettext-runtime/configure" --host="$host" \
                --build="$(/bin/sh "$source_dir/build-aux/config.guess")" \
                --enable-static --disable-shared --with-included-gettext \
                --disable-java --disable-csharp --disable-libasprintf \
                > configure.log 2>&1
            make -C intl -j1 > build.log 2>&1
            test -s intl/.libs/libintl.a
            test -s intl/libintl.h
            touch complete
        )
    fi
    libraries+=("$work/intl/.libs/libintl.a")
    if [[ "$architecture" == arm64 ]]; then
        cp "$work/intl/libintl.h" "$output/include/libintl.h"
    else
        cmp "$work/intl/libintl.h" "$output/include/libintl.h"
    fi
done
xcrun lipo -create "${libraries[@]}" -output "$output/libintl.a"
cp "$source_dir/gettext-runtime/intl/COPYING.LIB" "$output/COPYING.LIB"
