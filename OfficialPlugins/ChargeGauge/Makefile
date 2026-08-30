.PHONY: all bundle embedded inspect clean
.DELETE_ON_ERROR:

SDK_ROOT ?= ../../PluginSDK
DEVELOPER_DIR ?= $(shell xcode-select -p)
SDK ?= iphoneos
TARGET ?= arm64-apple-ios12.0
BUILD_DIR ?= $(CURDIR)/build

PLUGIN_IDENTIFIER := com.torrekie.battman.plugin.charge-gauge
EXECUTABLE_NAME := BattmanChargeGauge
BUNDLE_DIR := $(BUILD_DIR)/$(EXECUTABLE_NAME).bundle
BUNDLE_EXECUTABLE := $(BUNDLE_DIR)/$(EXECUTABLE_NAME)
EMBEDDED_OBJECT := $(BUILD_DIR)/$(EXECUTABLE_NAME).embedded.o
PLUGIN_VERSION := $(shell tr -d '\r\n' < VERSION)
BUILD_VERSION := $(shell tr -d '\r\n' < BUILD_VERSION)
CLANG := DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK) clang
SDKROOT := $(shell DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK) --show-sdk-path)

PUBLIC_HEADERS := \
	$(SDK_ROOT)/include/BattmanPluginABI.h \
	$(SDK_ROOT)/include/BAAnalyticsCard.h \
	$(SDK_ROOT)/include/BAAnalyticsMetricSnapshot.h
LOCALIZATIONS := \
	Resources/en.lproj/Localizable.strings \
	Resources/de.lproj/Localizable.strings \
	Resources/zh-Hans.lproj/Localizable.strings \
	Resources/zh-Hant.lproj/Localizable.strings
COMMON_FLAGS := \
	-target $(TARGET) -isysroot "$(SDKROOT)" \
	-fobjc-arc -fblocks -fvisibility=hidden -fno-ident \
	-Wall -Wextra -Werror -Wno-deprecated-declarations \
	-I"$(SDK_ROOT)/include" -I. \
	-DBT_CHARGE_GAUGE_PLUGIN_VERSION=\"$(BUILD_VERSION)\"
FRAMEWORKS := \
	-framework Foundation -framework UIKit \
	-framework QuartzCore -framework CoreGraphics

all: bundle embedded inspect

bundle: $(BUNDLE_EXECUTABLE)

embedded: $(EMBEDDED_OBJECT)

$(BUNDLE_EXECUTABLE): BTChargeGaugePlugin.m BTChargeGaugePlugin.h Info.plist \
	VERSION BUILD_VERSION $(PUBLIC_HEADERS) $(LOCALIZATIONS)
	test "$(PLUGIN_VERSION)" = "$(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
	test "$(BUILD_VERSION)" = "$(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
	mkdir -p "$(BUNDLE_DIR)"
	cp Info.plist "$(BUNDLE_DIR)/Info.plist"
	for localization in Resources/*.lproj; do cp -R "$$localization" "$(BUNDLE_DIR)/"; done
	$(CLANG) $(COMMON_FLAGS) -bundle -Wl,-dead_strip -Wl,-no_uuid \
		-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
		BTChargeGaugePlugin.m $(FRAMEWORKS) -o "$@"
	codesign --force --sign - --timestamp=none --identifier "$(PLUGIN_IDENTIFIER)" "$(BUNDLE_DIR)"

$(EMBEDDED_OBJECT): BTChargeGaugePlugin.m BTChargeGaugePlugin.h \
	VERSION BUILD_VERSION $(PUBLIC_HEADERS)
	mkdir -p "$(BUILD_DIR)"
	$(CLANG) $(COMMON_FLAGS) -DBT_PLUGIN_EMBEDDED=1 \
		-c BTChargeGaugePlugin.m -o "$@"

inspect: $(BUNDLE_EXECUTABLE)
	"$(SDK_ROOT)/Tools/validate-native-bundle.sh" "$(BUNDLE_DIR)" \
		"$(PLUGIN_IDENTIFIER)" BattmanPluginEntryPointV1

clean:
	rm -rf "$(BUILD_DIR)"
