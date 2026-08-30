.PHONY: all source-membership-check publish_mounted_site publish_local_site publish_none clean FORCE
.DELETE_ON_ERROR:

# Please make sure this is synced with xcodeproj
# Pull version from repo root VERSION file to avoid drift.
BATTMAN_VERSION := $(shell cat ../VERSION)

SED = sed

IPHONEOS_DEPLOYMENT_TARGET := 12.0
export IPHONEOS_DEPLOYMENT_TARGET

LOCAL_IP := $(shell if command -v ip >/dev/null 2>&1; then \
	ip addr | $(SED) -n "s/.*inet \([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\)[ \\/].*/\1/p" | tail -1; \
	elif command -v ipconfig >/dev/null 2>&1; then \
		ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true; \
	fi)

THEOS ?= $(HOME)/theos
SDKROOT := ${THEOS}/sdks/iPhoneOS13.7.sdk

LIBS := -lobjc -Wl,-weak-lIOAccessoryManager -lsqlite3 -lc++
FRAMEWORKS := -framework UIKit \
	      -framework Foundation \
	      -framework CoreGraphics \
	      -framework CoreText \
	      -framework QuartzCore \
              -framework IOKit \
              -framework WebKit \
	      -framework SystemConfiguration \
	      -framework MessageUI \
	      -framework UserNotifications \
	      -framework Security \
	      -framework Metal \
	      -framework CoreImage

CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Werror -target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET} -target arm64-apple-darwin -fobjc-arc -fconstant-cfstrings -I. -I./EXTERNAL_HEADERS -DUSE_MOBILEGESTALT -DBATTMAN_VERSION_STRING=\"$(BATTMAN_VERSION)\"
BUILD_IDENTITY := build/preprocessed/BattmanBuildIdentity.json
LDFLAGS = -target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) -target arm64-apple-darwin $(LIBS) $(FRAMEWORKS) -Wl,-dead_strip_dylibs -Wl,-sectcreate,__TEXT,__btidentity,$(BUILD_IDENTITY)
ifeq ($(wildcard ${SDKROOT}),)
	SDKROOT = $(firstword $(wildcard ${THEOS}/sdks/iPhoneOS14.*.sdk))
endif
ifeq ($(shell test -e ../.git && echo exists), exists)
COMMIT_HASH := $(shell git rev-parse --short HEAD)
else
COMMIT_HASH :=
endif

ifneq (${RELEASE},1)
CFLAGS += -DDEBUG -Wno-error=\#warnings
PLIST_ICON_KEY := CFBundleIconsDISABLED
BUILD_CONFIGURATION := Debug
else
ICON_IF_RELEASE := build/Payload/Battman.app/1024.png
PLIST_ICON_KEY := CFBundleIcons
BUILD_CONFIGURATION := Release
endif

ifneq ($(wildcard ${THEOS}/toolchain/linux/iphone/bin/clang),)
CC = ${THEOS}/toolchain/linux/iphone/bin/clang
CFLAGS += -isysroot $(SDKROOT)
LDFLAGS += -isysroot $(SDKROOT)
NO_CLANGRT=1
else ifneq ($(wildcard /Applications/Xcode.app),)
CC = xcrun -sdk iphoneos cc
else
CC = cc
CFLAGS += -isysroot $(SDKROOT)
LDFLAGS += -isysroot $(SDKROOT)
# FIXME: This should be dynamically checked by filepath or something
NO_CLANGRT=1
endif

ifneq ($(wildcard ${THEOS}/toolchain/linux/iphone/bin/ldid),)
CODESIGN = ${THEOS}/toolchain/linux/iphone/bin/ldid -S
else ifneq ($(shell which ldid),)
CODESIGN = ldid -S
else ifneq ($(shell which codesign),)
# nessessary space
CODESIGN = codesign -f -s --entitlements
else
CODESIGN = echo "UNSIGNED: "
endif

ifneq (,$(wildcard ./mount/pub_html))
	PUBLISH_TARGET := publish_mounted_site
else ifneq (,$(wildcard /var/www/html/files))
	PUBLISH_TARGET := publish_local_site
else ifneq (,$(wildcard /srv/http/files))
	PUBLISH_TARGET := publish_local_site_srv
else
	PUBLISH_TARGET := publish_none
endif

# Production sources are deliberately explicit. Keep this manifest in sync with
# Xcode target membership; do not use a recursive wildcard here. In particular,
# files under Plugins/, examples, fixtures, and tests must never enter the host
# build merely because they appeared on disk.
ROOT_OBJC_SOURCES := \
	BatteryDetailsViewController.m \
	BatteryInfoViewController.m \
	BattmanPrefs.m \
	BrightnessAdvancedViewController.m \
	BrightnessCardCell.m \
	BrightnessDetailsViewController.m \
	CardProgressView.m \
	ChargingLimitViewController.m \
	ChargingManagementViewController.m \
	ColorSegProgressView.m \
	CrashLogger.m \
	DatePickerCompactButton.m \
	DatePickerTableViewCell.m \
	DonationPrompter.m \
	DonationViewController.m \
	FooterHyperlinkView.m \
	FullSMCViewController.m \
	GradientArcView.m \
	GradientHDRView.m \
	GradientSDRView.m \
	LanguageSelectionViewController.m \
	MultilineViewCell.m \
	PLBatteryUIMoveableGraphView.m \
	PLGraphViewTableCell.m \
	PickerAccessoryView.m \
	PreferencesViewController.m \
	SPWaterProgressIndicatorView.m \
	SVG.m \
	ScrollableDetailCell.m \
	SegmentedTextField.m \
	SegmentedViewCell.m \
	SettingsViewController.m \
	SimpleTemperatureViewController.m \
	SliderTableViewCell.m \
	ThermAniTestViewController.m \
	ThermalTunesViewContoller.m \
	UILabel+SFSymbolsOverride.m \
	UITextFieldStepper.m \
	UPSMonitor-new.m \
	UPSMonitor.m \
	VirtBriCardCell.m \
	WarnAccessoryView.m \
	main.m

ROOT_C_SOURCES := \
	BatterySubscriberViewControllerBase.c \
	CompatibilityHelper.c \
	CreditViewController.c \
	common.c

BATTERY_CELL_SOURCES := \
	BatteryCellView/BatteryCellView.m \
	BatteryCellView/BatteryInfoTableViewCell.m \
	BatteryCellView/BrightnessInfoTableViewCell.m \
	BatteryCellView/TemperatureInfoTableViewCell.m

ICON_SOURCES := \
	CGIconSet/BattmanVectorIcon.m \
	CGIconSet/DesktopVectorIcon.m \
	CGIconSet/IPadHomeButtonVectorIcon.m \
	CGIconSet/IPadVectorIcon.m \
	CGIconSet/IPhoneD7VectorIcon.m \
	CGIconSet/IPhoneHomeButtonVectorIcon.m \
	CGIconSet/IPhoneVectorIcon.m \
	CGIconSet/NightShiftVectorIcon.m \
	CGIconSet/TrueToneVectorIcon.m

OBJC_EXTENSION_SOURCES := \
	ObjCExt/CALayer+smoothCorners.m \
	ObjCExt/NSBundle+Auto.m \
	ObjCExt/NSData+HexString.m \
	ObjCExt/UIColor+compat.m \
	ObjCExt/UIImage+SVG.m \
	ObjCExt/UIScreen+Auto.m

SEGMENT_CONTROL_SOURCES := \
	UberSegmentedControl/Constants.m \
	UberSegmentedControl/DividerView.m \
	UberSegmentedControl/MultiSelectSegmentedControl.m \
	UberSegmentedControl/SegmentButton.m \
	UberSegmentedControl/StackViewGestureHandler.m \
	UberSegmentedControl/UIView+Fill.m \
	UberSegmentedControl/UberSegmentedControl.m

ANALYTICS_SOURCES := \
	Features/Analytics/BuiltIn/BAAnalyticsBatterySummaryCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsBuiltInCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsBuiltInCards.m \
	Features/Analytics/BuiltIn/BAAnalyticsBuiltInPlugin.m \
	Features/Analytics/BuiltIn/BAAnalyticsChargingLimitCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsCycleSummaryCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsPowerAverageCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsRemainingCapacityCard.m \
	Features/Analytics/BuiltIn/BAAnalyticsTemperatureAverageCard.m \
	Features/Analytics/Data/BAAnalyticsMetricService.m \
	Features/Analytics/Data/BAAnalyticsSystemMetricSource.m \
	Features/Analytics/Host/AnalyticsCardCell.m \
	Features/Analytics/Host/AnalyticsCardGridLayout.m \
	Features/Analytics/Host/AnalyticsViewController.m \
	Features/Analytics/Host/BAAnalyticsCardLayoutStore.m \
	Features/Analytics/Host/BAAnalyticsUnavailableCard.m \
	Features/Analytics/Public/BAAnalyticsMetricSnapshot.m

PLUGIN_HOST_SOURCES := \
	PluginHost/Application/BTPluginApplicationIntegration.m \
	PluginHost/Application/BTPluginPlatform.m \
	PluginHost/BTEmbeddedPluginRegistration.m \
	PluginHost/BTPluginExtensionDescriptor.m \
	PluginHost/BTPluginIdentifiers.m \
	PluginHost/BTPluginRegistry.m \
	PluginHost/Discovery/BTPluginDiscovery.m \
	PluginHost/Import/BTPluginApplicationDataStore.m \
	PluginHost/Import/BTPluginImportCoordinator.m \
	PluginHost/Import/BTPluginQuarantineStore.m \
	PluginHost/Management/BTPluginManagementLineage.m \
	PluginHost/Management/BTPluginManagementService.m \
	PluginHost/Model/BTPluginPackageErrors.m \
	PluginHost/Model/BTPluginPackageManifest.m \
	PluginHost/Model/BTPluginSource.m \
	PluginHost/Runtime/BTPluginActivationStore.m \
	PluginHost/Runtime/BTPluginApplicationDataTransaction.m \
	PluginHost/Runtime/BTPluginNativeImageLoader.m \
	PluginHost/Runtime/BTPluginRuntimeEnvironment.m \
	PluginHost/Runtime/BTPluginRuntimeLoader.m \
	PluginHost/Runtime/BTPluginSafeModeRequest.m \
	PluginHost/Security/BTPluginMachOInspector.m \
	PluginHost/Security/BTPluginP256.m \
	PluginHost/Security/BTPluginPackageStructuralVerifier.m \
	PluginHost/Security/BTPluginPackageVerifier.m \
	PluginHost/Security/BTPluginPlatformLoadabilityVerifier.m \
	PluginHost/Security/BTPluginSealedPackageStructuralVerifier.m \
	PluginHost/Security/BTPluginSignatureVerifier.m \
	PluginHost/Security/BTPluginTrustEvaluator.m \
	PluginHost/Security/BTPluginTrustMetadataVerifier.m \
	PluginHost/Security/BTPluginOfficialTrustLoader.m \
	PluginHost/Security/BTPluginTrustStore.m \
	PluginHost/UI/BTPluginImportPresenter.m \
	PluginHost/UI/BTPluginManagementViewController.m

BATTERY_UTILITY_SOURCES := \
	battery_utils/bin_display.m \
	battery_utils/hid.m \
	battery_utils/accessory.c \
	battery_utils/battery_diagnostics.c \
	battery_utils/battery_info.c \
	battery_utils/daemon.c \
	battery_utils/iokit_connection.c \
	battery_utils/libsmc.c \
	battery_utils/pmnotification.c \
	battery_utils/thermal.c \
	battery_utils/worker.c

BRIGHTNESS_SOURCES := \
	brightness/BSC_Provider.m \
	brightness/backlight-control.c \
	brightness/dcp.c

LOW_LEVEL_SOURCES := \
	hw/IOMFB_interaction.c \
	license/localized.c \
	scprefs/wrapper.c \
	security/selfcheck.c

ASSEMBLY_SOURCES := \
	license/licensing.S \
	security/protect.S

SOURCES := \
	$(ROOT_OBJC_SOURCES) \
	$(ANALYTICS_SOURCES) \
	$(PLUGIN_HOST_SOURCES) \
	$(ROOT_C_SOURCES) \
	$(BATTERY_CELL_SOURCES) \
	$(ICON_SOURCES) \
	$(OBJC_EXTENSION_SOURCES) \
	$(SEGMENT_CONTROL_SOURCES) \
	$(BATTERY_UTILITY_SOURCES) \
	$(BRIGHTNESS_SOURCES) \
	$(LOW_LEVEL_SOURCES) \
	$(ASSEMBLY_SOURCES)

# The historical Phase 0 manager prototype was split into the reviewed
# PluginHost implementation and is not retained in the production tree.
# Keep this classification explicit so reintroducing a prototype requires a
# deliberate source-membership update.
PROTOTYPE_SOURCES :=

# These dormant test helpers were selected only by the old wildcard and are not
# members of any Xcode application target.
DEVELOPMENT_ONLY_SOURCES := battery_utils/smctest.c license/test.S

# Wildcards are permitted only for the audit. Any new source must be classified
# above before the build can proceed.
DISCOVERED_SOURCE_FILES := $(sort $(shell find . -path ./build -prune -o -type f \( -name '*.m' -o -name '*.c' -o -name '*.S' \) -print | $(SED) 's|^\./||'))
CLASSIFIED_NONPRODUCTION_SOURCES := $(PROTOTYPE_SOURCES) $(DEVELOPMENT_ONLY_SOURCES)
UNCLASSIFIED_SOURCE_FILES := $(filter-out $(SOURCES) $(CLASSIFIED_NONPRODUCTION_SOURCES),$(DISCOVERED_SOURCE_FILES))
MISSING_CLASSIFIED_SOURCE_FILES := $(filter-out $(DISCOVERED_SOURCE_FILES),$(SOURCES) $(CLASSIFIED_NONPRODUCTION_SOURCES))
PROTOTYPE_BUILD_LEAKS := $(filter $(PROTOTYPE_SOURCES),$(SOURCES))

PRESRC := $(addprefix build/preprocessed/,$(SOURCES))
OBJECTS:=$(addprefix build/objects/,$(addsuffix .o,$(SOURCES)))
#OBJECTS := $(subst build/preprocessed,build/objects,$(addsuffix .o,$(PRESRC)))
POBJECTS := build/objects/license/constants.c.o \
		build/objects/localization_data.c.o
ifeq ($(NO_CLANGRT),1)
POBJECTS += build/objects/isOSVersionAtLeast.S.o
endif

source-membership-check:
	@if test -n "$(UNCLASSIFIED_SOURCE_FILES)"; then \
		printf '%s\n' "Unclassified source files: $(UNCLASSIFIED_SOURCE_FILES)"; \
		exit 1; \
	fi
	@if test -n "$(MISSING_CLASSIFIED_SOURCE_FILES)"; then \
		printf '%s\n' "Classified source files missing from disk: $(MISSING_CLASSIFIED_SOURCE_FILES)"; \
		exit 1; \
	fi
	@if test -n "$(PROTOTYPE_BUILD_LEAKS)"; then \
		printf '%s\n' "Prototype sources selected for production: $(PROTOTYPE_BUILD_LEAKS)"; \
		exit 1; \
	fi
	@printf '%s\n' "Source membership verified: $(words $(SOURCES)) production, $(words $(PROTOTYPE_SOURCES)) prototype, $(words $(DEVELOPMENT_ONLY_SOURCES)) development-only."

all: $(PUBLISH_TARGET)

build/preprocessed/isOSVersionAtLeast.S:
	@mkdir -p $(@D)
	echo ".section __TEXT,__text,regular,pure_instructions">$@
	echo ".globl ___isOSVersionAtLeast">>$@
	echo ".p2align 2">>$@
	echo "___isOSVersionAtLeast:">>$@
	echo "b ____isOSVersionAtLeast">>$@
build/preprocessed/license/constants.c: license/license.html
	@mkdir -p $(@D)
	echo "const unsigned char lh_arr[]={">$@
	sha256sum license/license.html|$(SED) "s/ .*$$//g;s/.\\{2\\}/0x\\0,/g;s/,$$//g">>$@
	#openssl sha256 -c license/license.html|$(SED) "s/^.*= /0x/g;s/:/,0x/g" >>$@
	echo "};">>$@
build/preprocessed/localization_data.c: Localizations/*.po Localizations/base.pot Localizations/*.sh
	@mkdir -p $(@D)
	./Localizations/generate_code.sh>$@

$(OBJECTS): build/objects/%.o: %
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -I./$(subst build/preprocessed,,$(dir $<)) -c $< -o $@

# Public Analytics sources forward to the canonical SDK headers. Make cannot
# discover those transitive imports itself, so rebuild every Analytics object
# whenever the canonical public contract changes.
$(filter build/objects/Features/Analytics/%,$(OBJECTS)): \
	../PluginSDK/include/BAAnalyticsCard.h \
	../PluginSDK/include/BAAnalyticsMetricSnapshot.h \
	../PluginSDK/include/BattmanPluginABI.h
$(POBJECTS): build/objects/%.o: build/preprocessed/%
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -I.$(dir $<) -c $< -o $@

$(BUILD_IDENTITY): ../VERSION ../Scripts/Build/generate-build-identity.py ../Scripts/Release/host_build_identity.py Makefile FORCE
	@mkdir -p $(@D)
	PYTHONDONTWRITEBYTECODE=1 python3 ../Scripts/Build/generate-build-identity.py \
		--repo .. --version "$(BATTMAN_VERSION)" \
		--configuration "$(BUILD_CONFIGURATION)" \
		--product-identifier com.torrekie.Battman --output $@

build/Payload/Battman.app/Battman: $(OBJECTS) $(POBJECTS) $(BUILD_IDENTITY) ../Battman.entitlements ../VERSION Makefile | source-membership-check
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) $(filter %.o,$^) -o $@
	$(CODESIGN)../Battman.entitlements $@
	PYTHONDONTWRITEBYTECODE=1 python3 ../Scripts/Build/verify-build-identity.py \
		--repo .. --executable $@ --version "$(BATTMAN_VERSION)" \
		--configuration "$(BUILD_CONFIGURATION)" \
		--product-identifier com.torrekie.Battman
build/Payload/Battman.app/Info.plist: Info.plist ../VERSION Makefile
	@mkdir -p $(@D)
	$(SED) 's/\$$(CURRENT_PROJECT_VERSION)/$(BATTMAN_VERSION)/;s/\$$(MARKETING_VERSION)/$(BATTMAN_VERSION)/;s/\$$(DEVELOPMENT_LANGUAGE)/en/;s/\$$(EXECUTABLE_NAME)/Battman/;s/\$$(PRODUCT_BUNDLE_IDENTIFIER)/com.torrekie.Battman/;s/\$$(PRODUCT_NAME)/Battman/;s/\$$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/;s/\$$(COMMIT_HASH)/$(COMMIT_HASH)/;s/\$$(CONFIGURATION)/$(BUILD_CONFIGURATION)/;s/CFBundleIcons/$(PLIST_ICON_KEY)/' Info.plist > $@

build/Payload/Battman.app/1024.png: ../Battman.svg
	@mkdir -p $(@D)
	./generate_icons.sh ../Battman.svg build/Payload/Battman.app/

build/Payload/Battman.app/license.html: license/license.html
	@mkdir -p $(@D)
	cp $^ $@

build/%/BattmanIcons@2x.artwork: ../BattmanIcons@2x.artwork
	cp $< $@
build/%/BattmanIcons@3x.artwork: ../BattmanIcons@3x.artwork
	cp $< $@


.PHONY: install-plugin-trust-resources
install-plugin-trust-resources: build/Payload/Battman.app/Info.plist
	PYTHONDONTWRITEBYTECODE=1 python3 ../Scripts/Build/install-plugin-trust-resources.py \
		--source ../OfficialPlugins/Trust/PluginTrust --app build/Payload/Battman.app

build/Battman.ipa: build/Payload/Battman.app/Battman build/Payload/Battman.app/Info.plist ${ICON_IF_RELEASE} build/Payload/Battman.app/license.html build/Payload/Battman.app/BattmanIcons@2x.artwork build/Payload/Battman.app/BattmanIcons@3x.artwork | install-plugin-trust-resources
	cd build/ && zip -r Battman.ipa ./Payload

%/Battman.ipa: build/Battman.ipa
	cp $< $@

%/index.html: %/install_template.html build/Battman.ipa
	$(SED) 's/LOCAL_IP/${LOCAL_IP}/;s/LATEST_UPDATE/$(shell date)/' $(filter %.html,$^)>$@

publish_mounted_site: mount/pub_html/battman/ \
			mount/pub_html/battman/Battman.ipa \
			mount/pub_html/battman/index.html
	@echo Install on your site.

publish_local_site: /var/www/html/files/battman \
			/var/www/html/files/battman/Battman.ipa \
			/var/www/html/files/battman/index.html
	@echo Install at: ${LOCAL_IP}
publish_local_site_srv: /srv/http/files/battman \
			/srv/http/files/battman/Battman.ipa \
			/srv/http/files/battman/index.html
	@echo Install at: ${LOCAL_IP}

publish_none: build/Battman.ipa
	@echo Not publishing.

clean:
	rm -rf build/
