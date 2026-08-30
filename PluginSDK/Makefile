.PHONY: all example example-bundle example-embedded inspect
.DELETE_ON_ERROR:

# Standalone Battman Plugin SDK build. It intentionally imports no host source.
DEVELOPER_DIR ?= $(shell xcode-select -p)
SDK ?= iphoneos
TARGET ?= arm64-apple-ios12.0
BUILD_DIR ?= $(CURDIR)/build
XCRUN := DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK)
CLANG := $(XCRUN) clang
SDKROOT := $(shell DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --sdk $(SDK) --show-sdk-path)

INCLUDE_DIR := $(CURDIR)/include
EXAMPLE_DIR := $(CURDIR)/Examples/AnalyticsCard
EXAMPLE_SOURCE := $(EXAMPLE_DIR)/BTAnalyticsExamplePlugin.m
EXAMPLE_HEADER := $(EXAMPLE_DIR)/BTAnalyticsExamplePlugin.h
EXAMPLE_BUILD_VERSION_FILE := $(EXAMPLE_DIR)/BUILD_VERSION
EXAMPLE_BUILD_VERSION := $(shell tr -d '\r\n' < "$(EXAMPLE_BUILD_VERSION_FILE)")
PUBLIC_HEADERS := \
	$(INCLUDE_DIR)/BattmanPluginABI.h \
	$(INCLUDE_DIR)/BAAnalyticsCard.h \
	$(INCLUDE_DIR)/BAAnalyticsMetricSnapshot.h
BUNDLE_DIR := $(BUILD_DIR)/BTAnalyticsExample.bundle
BUNDLE_EXECUTABLE := $(BUNDLE_DIR)/BTAnalyticsExample
EMBEDDED_OBJECT := $(BUILD_DIR)/BTAnalyticsExample.embedded.o

COMMON_FLAGS := \
	-target $(TARGET) \
	-isysroot "$(SDKROOT)" \
	-fobjc-arc -fblocks -fvisibility=hidden \
	-Wall -Wextra -Werror -Wno-deprecated-declarations \
	-I"$(INCLUDE_DIR)" -I"$(EXAMPLE_DIR)" \
	-DBT_ANALYTICS_EXAMPLE_PLUGIN_VERSION=\"$(EXAMPLE_BUILD_VERSION)\"
APPLE_FRAMEWORKS := \
	-framework Foundation \
	-framework UIKit \
	-framework QuartzCore \
	-framework CoreGraphics

all: example

example: example-bundle example-embedded inspect

example-bundle: $(BUNDLE_EXECUTABLE)

example-embedded: $(EMBEDDED_OBJECT)

$(BUNDLE_EXECUTABLE): $(EXAMPLE_SOURCE) $(EXAMPLE_HEADER) $(PUBLIC_HEADERS) \
	$(EXAMPLE_DIR)/Info.plist $(EXAMPLE_BUILD_VERSION_FILE)
	test "$(EXAMPLE_BUILD_VERSION)" = "$(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $(EXAMPLE_DIR)/Info.plist)"
	mkdir -p "$(BUNDLE_DIR)"
	cp "$(EXAMPLE_DIR)/Info.plist" "$(BUNDLE_DIR)/Info.plist"
	$(CLANG) $(COMMON_FLAGS) -bundle -Wl,-dead_strip \
		-Wl,-exported_symbol,_BattmanPluginEntryPointV1 \
		"$(EXAMPLE_SOURCE)" $(APPLE_FRAMEWORKS) -o "$@"
	codesign --force --sign - --identifier com.torrekie.battman.example.analytics "$(BUNDLE_DIR)"

$(EMBEDDED_OBJECT): $(EXAMPLE_SOURCE) $(EXAMPLE_HEADER) $(PUBLIC_HEADERS) \
	$(EXAMPLE_BUILD_VERSION_FILE)
	mkdir -p "$(BUILD_DIR)"
	$(CLANG) $(COMMON_FLAGS) -DBT_PLUGIN_EMBEDDED=1 -c "$(EXAMPLE_SOURCE)" -o "$@"

inspect: $(BUNDLE_EXECUTABLE)
	"$(CURDIR)/Tools/validate-native-bundle.sh" "$(BUNDLE_DIR)" \
		com.torrekie.battman.example.analytics BattmanPluginEntryPointV1
