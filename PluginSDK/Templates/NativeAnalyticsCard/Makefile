.PHONY: all inspect
.DELETE_ON_ERROR:

SDK_ROOT ?= ../..
DEVELOPER_DIR ?= $(shell xcode-select -p)
SDK ?= iphoneos
TARGET ?= arm64-apple-ios12.0
BUILD_DIR ?= $(CURDIR)/build
PLUGIN_IDENTIFIER ?= com.example.battman.analytics-card
EXECUTABLE_NAME := BTAnalyticsExample
BUILD_VERSION := $(shell tr -d '\r\n' < BUILD_VERSION)
BUNDLE_DIR := $(BUILD_DIR)/$(EXECUTABLE_NAME).bundle
BUNDLE_EXECUTABLE := $(BUNDLE_DIR)/$(EXECUTABLE_NAME)
CLANG := DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK) clang
SDKROOT := $(shell DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK) --show-sdk-path)

all: $(BUNDLE_EXECUTABLE) inspect

$(BUNDLE_EXECUTABLE): BTAnalyticsExamplePlugin.m BTAnalyticsExamplePlugin.h \
	Info.plist BUILD_VERSION \
	$(SDK_ROOT)/include/BattmanPluginABI.h \
	$(SDK_ROOT)/include/BAAnalyticsCard.h \
	$(SDK_ROOT)/include/BAAnalyticsMetricSnapshot.h
	test "$(BUILD_VERSION)" = "$(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
	mkdir -p "$(BUNDLE_DIR)"
	cp Info.plist "$(BUNDLE_DIR)/Info.plist"
	$(CLANG) -target $(TARGET) -isysroot "$(SDKROOT)" \
		-fobjc-arc -fblocks -fvisibility=hidden \
		-Wall -Wextra -Werror -Wno-deprecated-declarations \
		-I"$(SDK_ROOT)/include" -I. -bundle -Wl,-dead_strip \
		-DBT_ANALYTICS_EXAMPLE_PLUGIN_VERSION=\"$(BUILD_VERSION)\" \
		-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
		BTAnalyticsExamplePlugin.m -framework Foundation -framework UIKit \
		-framework QuartzCore -framework CoreGraphics -o "$@"
	codesign --force --sign - --identifier "$(PLUGIN_IDENTIFIER)" "$(BUNDLE_DIR)"

inspect: $(BUNDLE_EXECUTABLE)
	"$(SDK_ROOT)/Tools/validate-native-bundle.sh" "$(BUNDLE_DIR)" \
		"$(PLUGIN_IDENTIFIER)" BattmanPluginEntryPointV1
