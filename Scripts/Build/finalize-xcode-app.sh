#!/bin/sh
# Finalize one Xcode-built Battman.app. Release archives are assembled only by
# Scripts/Release, never inside the build graph.

set -eu

: "${PROJECT_DIR:?PROJECT_DIR is required}"
: "${CODESIGNING_FOLDER_PATH:?CODESIGNING_FOLDER_PATH is required}"
: "${PLATFORM_NAME:?PLATFORM_NAME is required}"
: "${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
: "${CONFIGURATION:?CONFIGURATION is required}"
: "${PRODUCT_BUNDLE_IDENTIFIER:?PRODUCT_BUNDLE_IDENTIFIER is required}"

app_path=${CODESIGNING_FOLDER_PATH}
executable_name=${EXECUTABLE_NAME:-Battman}
executable_path="${app_path}/${executable_name}"
info_plist="${app_path}/Info.plist"

if [ ! -d "${app_path}" ] || [ ! -f "${info_plist}" ]; then
    echo "error: incomplete Xcode app product: ${app_path}" >&2
    exit 2
fi

PYTHONDONTWRITEBYTECODE=1 python3 \
    "${PROJECT_DIR}/Scripts/Build/verify-build-identity.py" \
    --repo "${PROJECT_DIR}" \
    --executable "${executable_path}" \
    --version "${CURRENT_PROJECT_VERSION}" \
    --configuration "${CONFIGURATION}" \
    --product-identifier "${PRODUCT_BUNDLE_IDENTIFIER}"

commit_hash=${COMMIT_HASH:-}
if [ -z "${commit_hash}" ]; then
    commit_hash=$(git -C "${PROJECT_DIR}" rev-parse --short HEAD)
fi

if ! /usr/libexec/PlistBuddy -c "Set :GIT_COMMIT_HASH ${commit_hash}" "${info_plist}"; then
    /usr/libexec/PlistBuddy -c "Add :GIT_COMMIT_HASH string ${commit_hash}" "${info_plist}"
fi
build_configuration=${CONFIGURATION:-Unknown}
if ! /usr/libexec/PlistBuddy -c "Set :BTBuildConfiguration ${build_configuration}" "${info_plist}"; then
    /usr/libexec/PlistBuddy -c "Add :BTBuildConfiguration string ${build_configuration}" "${info_plist}"
fi

sh "${PROJECT_DIR}/Battman/generate_icons.sh" \
    "${PROJECT_DIR}/Battman.svg" "${app_path}/"

# The canonical source is intentionally absent until reviewed public root keys
# and signed metadata exist. The installer is a no-op only when both source and
# destination are absent, and otherwise refuses links, stale output, or merges.
PYTHONDONTWRITEBYTECODE=1 python3 \
    "${PROJECT_DIR}/Scripts/Build/install-plugin-trust-resources.py" \
    --source "${PROJECT_DIR}/OfficialPlugins/Trust/PluginTrust" \
    --app "${app_path}"

if [ "${PLATFORM_NAME}" = "iphoneos" ]; then
    if [ ! -f "${executable_path}" ]; then
        echo "error: app executable is missing: ${executable_path}" >&2
        exit 2
    fi
    signing_tool=${BATTMAN_CODESIGN_TOOL:-auto}
    if { [ "${signing_tool}" = auto ] || [ "${signing_tool}" = ldid ]; } && \
            command -v ldid >/dev/null 2>&1; then
        ldid -S"${PROJECT_DIR}/Battman.entitlements" "${executable_path}"
        ldid -h "${executable_path}" >/dev/null
    elif { [ "${signing_tool}" = auto ] || [ "${signing_tool}" = codesign ]; } && \
            command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --entitlements "${PROJECT_DIR}/Battman.entitlements" \
            --generate-entitlement-der "${app_path}"
        codesign --verify --strict "${app_path}"
    else
        echo "error: iphoneos finalization requires ldid or Apple codesign" >&2
        exit 2
    fi
fi
