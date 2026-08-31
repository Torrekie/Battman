#!/bin/sh

set -eu

export PYTHONDONTWRITEBYTECODE=1

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/battman-plugin-phase1.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

CLANG=$(xcrun --sdk macosx --find clang)
CLANGXX=$(xcrun --sdk macosx --find clang++)
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path)
IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

python3 "$REPO_ROOT/Tests/check-source-parity.py"
python3 "$REPO_ROOT/Tests/check-analytics-localizations.py"
python3 "$REPO_ROOT/Tests/check-plugin-localizations.py"
python3 "$REPO_ROOT/Tests/check-plugin-loader-boundary.py"
python3 "$REPO_ROOT/Tests/check-ups-monitor-startup.py"
python3 "$REPO_ROOT/Tests/check-charging-limit-daemon-safety.py"
python3 "$REPO_ROOT/Tests/check-analytics-metric-safety.py"
python3 "$REPO_ROOT/PluginSDK/Tools/generate-sdk-contract.py" --check
bash -n "$REPO_ROOT/Tests/Device/run-analytics-rooted-preflight.sh"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-std=c11 -Wall -Wextra -Werror \
	"$REPO_ROOT/Tests/PluginSDK/test_abi_layout.c" \
	-o "$TEST_TMP/abi-c"
"$TEST_TMP/abi-c"

"$CLANGXX" \
	-isysroot "$MACOS_SDK" \
	-x c++ -std=c++17 -Wall -Wextra -Werror \
	"$REPO_ROOT/Tests/PluginSDK/test_abi_layout.c" \
	-o "$TEST_TMP/abi-cxx"
"$TEST_TMP/abi-cxx"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginRegistryTests.m" \
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m" \
	-o "$TEST_TMP/registry-tests"
"$TEST_TMP/registry-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/Analytics/BAAnalyticsPhase2Tests.m" \
	"$REPO_ROOT/Battman/Features/Analytics/Public/BAAnalyticsMetricSnapshot.m" \
	"$REPO_ROOT/Battman/Features/Analytics/Data/BAAnalyticsMetricService.m" \
	"$REPO_ROOT/Battman/Features/Analytics/Host/BAAnalyticsCardLayoutStore.m" \
	-o "$TEST_TMP/analytics-phase2-tests"
"$TEST_TMP/analytics-phase2-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginPackageStructuralVerifierTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/structural-tests"
"$TEST_TMP/structural-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginTrustTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginP256.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSignatureVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustEvaluator.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustMetadataVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/trust-tests"
"$TEST_TMP/trust-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginOfficialTrustLoaderTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginP256.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustEvaluator.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustMetadataVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginOfficialTrustLoader.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSignatureVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/official-trust-loader-tests"
"$TEST_TMP/official-trust-loader-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginKeychainTrustStoreTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginP256.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustStore.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/keychain-tests"
"$TEST_TMP/keychain-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginDiscoveryTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Discovery/BTPluginDiscovery.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginSource.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/discovery-tests"
"$TEST_TMP/discovery-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginActivationStoreTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginActivationStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginApplicationDataTransaction.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginSource.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/activation-tests"
"$TEST_TMP/activation-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginSafeModeRequestTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginSafeModeRequest.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	-o "$TEST_TMP/safe-mode-tests"
"$TEST_TMP/safe-mode-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginRuntimeEnvironmentTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.m" \
	-o "$TEST_TMP/runtime-environment-tests"
"$TEST_TMP/runtime-environment-tests"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fPIC -bundle -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/Fixtures/NativeRuntimeFixture.m" \
	-o "$TEST_TMP/native-runtime-fixture.bundle"
codesign --force --sign - --identifier com.example.battman.runtime "$TEST_TMP/native-runtime-fixture.bundle"
"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginNativeImageLoaderTests.m" \
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginNativeImageLoader.m" \
	-o "$TEST_TMP/native-loader-tests"
"$TEST_TMP/native-loader-tests" \
	"$TEST_TMP/native-runtime-fixture.bundle" \
	"$TEST_TMP/native-runtime-constructor-ran"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -fvisibility=hidden -Wall -Wextra -Werror \
	-bundle -framework Foundation \
	-I"$REPO_ROOT/PluginSDK/include" \
	-I"$REPO_ROOT/PluginSDK/TestSupport/include" \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
	"$REPO_ROOT/Tests/PluginSDK/Fixtures/BTMockStatusPlugin.m" \
	-o "$TEST_TMP/mock-status-fixture.bundle"
codesign --force --sign - "$TEST_TMP/mock-status-fixture.bundle"
"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -fvisibility=hidden -Wall -Wextra -Werror \
	-bundle -framework Foundation \
	-I"$REPO_ROOT/PluginSDK/TestSupport/ABI/v1-initial" \
	-I"$REPO_ROOT/PluginSDK/TestSupport/include" \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
	"$REPO_ROOT/Tests/PluginSDK/Fixtures/BTOlderV1Plugin.m" \
	-o "$TEST_TMP/older-v1-fixture.bundle"
codesign --force --sign - "$TEST_TMP/older-v1-fixture.bundle"
"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation \
	"$REPO_ROOT/Tests/PluginHost/BTPluginGenericExtensionTests.m" \
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginNativeImageLoader.m" \
	-o "$TEST_TMP/generic-extension-tests"
"$TEST_TMP/generic-extension-tests" \
	"$TEST_TMP/mock-status-fixture.bundle" \
	"$TEST_TMP/older-v1-fixture.bundle"

"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-fvisibility=hidden -fPIC \
	-c "$REPO_ROOT/Tests/PluginHost/Fixtures/ConstructorSentinelPlugin.c" \
	-o "$TEST_TMP/constructor-fixture.o"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-fvisibility=hidden -fPIC \
	-DBT_PLUGIN_ADVERSARIAL_EXTRA_EXPORT=1 \
	-c "$REPO_ROOT/Tests/PluginHost/Fixtures/ConstructorSentinelPlugin.c" \
	-o "$TEST_TMP/extra-export-fixture.o"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios15.0 \
	-fvisibility=hidden -fPIC \
	-c "$REPO_ROOT/Tests/PluginHost/Fixtures/ConstructorSentinelPlugin.c" \
	-o "$TEST_TMP/chained-fixture.o"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-bundle -Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/valid.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/valid.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-fobjc-arc -fblocks -fvisibility=hidden \
	-I"$REPO_ROOT/PluginSDK/include" \
	-I"$REPO_ROOT/PluginSDK/Examples/AnalyticsCard" \
	-bundle -Wl,-dead_strip -Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$REPO_ROOT/PluginSDK/Examples/AnalyticsCard/BTAnalyticsExamplePlugin.m" \
	-framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
	-o "$TEST_TMP/valid-objective-c.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture \
	"$TEST_TMP/valid-objective-c.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios15.0 \
	-bundle -Wl,-fixup_chains -Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$TEST_TMP/chained-fixture.o" \
	-o "$TEST_TMP/valid-chained.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture \
	"$TEST_TMP/valid-chained.bundle"
cp "$TEST_TMP/valid.bundle" "$TEST_TMP/resigned.bundle"
codesign --force --sign - --timestamp=none --identifier com.example.battman.analytics.fixture \
	--entitlements "$REPO_ROOT/Battman.entitlements" "$TEST_TMP/resigned.bundle"
printf '\0' >> "$TEST_TMP/resigned.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-dynamiclib -Wl,-install_name,@rpath/Example.so \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/valid.so"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/valid.so"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-dynamiclib -Wl,-install_name,@rpath/Unexpected.so \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/unsafe-install-name.so"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/unsafe-install-name.so"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-bundle -Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-rpath,/tmp -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/unsafe-rpath.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/unsafe-rpath.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-bundle -Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-framework,IOKit -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/unsafe-dependency.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/unsafe-dependency.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-bundle -Wl,-flat_namespace -Wl,-undefined,dynamic_lookup \
	-Wl,-exported_symbol,_BattmanPluginEntryPointV1 -Wl,-no_uuid \
	"$TEST_TMP/constructor-fixture.o" \
	-o "$TEST_TMP/dynamic-lookup.bundle" 2>"$TEST_TMP/dynamic-lookup-link.log"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/dynamic-lookup.bundle"
"$CLANG" \
	-isysroot "$IPHONEOS_SDK" \
	-target arm64-apple-ios12.0 \
	-bundle -Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
	-Wl,-exported_symbol,_BattmanPluginUnexpectedExport -Wl,-no_uuid \
	"$TEST_TMP/extra-export-fixture.o" \
	-o "$TEST_TMP/extra-export.bundle"
codesign --force --sign - --identifier com.example.battman.analytics.fixture "$TEST_TMP/extra-export.bundle"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginMachOInspectorTests.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginMachOInspector.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPlatformLoadabilityVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/macho-tests"
"$TEST_TMP/macho-tests" \
	"$TEST_TMP/valid.bundle" \
	"$TEST_TMP/valid-objective-c.bundle" \
	"$TEST_TMP/valid-chained.bundle" \
	"$TEST_TMP/valid.so" \
	"$TEST_TMP/unsafe-install-name.so" \
	"$TEST_TMP/unsafe-rpath.bundle" \
	"$TEST_TMP/unsafe-dependency.bundle" \
	"$TEST_TMP/dynamic-lookup.bundle" \
	"$TEST_TMP/extra-export.bundle" \
	"$TEST_TMP/resigned.bundle"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginRuntimeLoaderTests.m" \
	"$REPO_ROOT/Tests/PluginHost/Fixtures/BTPluginSignedPackageFixture.m" \
	"$REPO_ROOT/Battman/PluginHost/BTEmbeddedPluginRegistration.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginExtensionDescriptor.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginRegistry.m" \
	"$REPO_ROOT/Battman/PluginHost/Discovery/BTPluginDiscovery.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginSource.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginActivationStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginApplicationDataTransaction.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginNativeImageLoader.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginRuntimeLoader.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginMachOInspector.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginP256.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPlatformLoadabilityVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSignatureVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustEvaluator.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageVerifier.m" \
	-o "$TEST_TMP/runtime-loader-tests"
"$TEST_TMP/runtime-loader-tests" "$TEST_TMP/valid.bundle"

"$CLANG" \
	-isysroot "$MACOS_SDK" \
	-fobjc-arc -fblocks -Wall -Wextra -Werror \
	-framework Foundation -framework Security \
	"$REPO_ROOT/Tests/PluginHost/BTPluginQuarantineTests.m" \
	"$REPO_ROOT/Tests/PluginHost/Fixtures/BTPluginSignedPackageFixture.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageErrors.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginPackageManifest.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginP256.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginMachOInspector.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPlatformLoadabilityVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginSignatureVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginTrustEvaluator.m" \
	"$REPO_ROOT/Battman/PluginHost/Security/BTPluginPackageVerifier.m" \
	"$REPO_ROOT/Battman/PluginHost/Import/BTPluginQuarantineStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Import/BTPluginImportCoordinator.m" \
	"$REPO_ROOT/Battman/PluginHost/Import/BTPluginApplicationDataStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Management/BTPluginManagementService.m" \
	"$REPO_ROOT/Battman/PluginHost/Management/BTPluginManagementLineage.m" \
	"$REPO_ROOT/Battman/PluginHost/Discovery/BTPluginDiscovery.m" \
	"$REPO_ROOT/Battman/PluginHost/Model/BTPluginSource.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginActivationStore.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginApplicationDataTransaction.m" \
	"$REPO_ROOT/Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.m" \
	"$REPO_ROOT/Battman/PluginHost/BTPluginIdentifiers.m" \
	-o "$TEST_TMP/quarantine-tests"
"$TEST_TMP/quarantine-tests" "$TEST_TMP/valid.bundle"

PYTHONDONTWRITEBYTECODE=1 python3 \
	"$REPO_ROOT/Tests/PluginHost/test_plugin_tools.py" \
	"$TEST_TMP/valid.bundle" \
	"$TEST_TMP/valid.so" \
	"$REPO_ROOT"

if strings "$TEST_TMP/macho-tests" | grep -Eq '(^|[^A-Za-z])(dlopen|dlsym|CFBundleLoadExecutable)([^A-Za-z]|$)'; then
	printf '%s\n' "Non-executing verifier binary unexpectedly references a loader API." >&2
	exit 1
fi

bash "$REPO_ROOT/Tests/PluginSDK/run-clean-room-sdk-tests.sh"
bash "$REPO_ROOT/Tests/Release/run-release-tool-tests.sh"

printf '%s\n' "Plugin ABI, Analytics, native runtime, SDK, and release-boundary tests passed."
