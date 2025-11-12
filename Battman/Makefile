.PHONY: all publish_mounted_site publish_local_site publish_none clean

# Please make sure this is synced with xcodeproj
BATTMAN_VERSION := 1.0.2

SED = sed

IPHONEOS_DEPLOYMENT_TARGET := 12.0
export IPHONEOS_DEPLOYMENT_TARGET

LOCAL_IP := $(shell ip addr | $(SED) -n "s/.*inet \([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\)[ \\/].*/\1/p" | tail -1)

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
	      -framework Metal \
	      -framework CoreImage

CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Werror -target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET} -target arm64-apple-darwin -fobjc-arc -fconstant-cfstrings -I./EXTERNAL_HEADERS -DUSE_MOBILEGESTALT -DBATTMAN_VERSION_STRING=\"$(BATTMAN_VERSION)\"
LDFLAGS = -target arm64-apple-ios$(IPHONEOS_DEPLOYMENT_TARGET) -target arm64-apple-darwin $(LIBS) $(FRAMEWORKS) -Wl,-dead_strip_dylibs
THEOS := ~/theos

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
else
ICON_IF_RELEASE := build/Payload/Battman.app/1024.png
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

SOURCES := $(wildcard *.m *.c */*.m */*.c */*.S)
PRESRC := $(addprefix build/preprocessed/,$(SOURCES))
OBJECTS:=$(addprefix build/objects/,$(addsuffix .o,$(SOURCES)))
#OBJECTS := $(subst build/preprocessed,build/objects,$(addsuffix .o,$(PRESRC)))
POBJECTS := build/objects/license/constants.c.o \
		build/objects/localization_data.c.o
ifeq ($(NO_CLANGRT),1)
POBJECTS += build/objects/isOSVersionAtLeast.S.o
endif

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
$(POBJECTS): build/objects/%.o: build/preprocessed/%
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -I.$(dir $<) -c $< -o $@

build/Payload/Battman.app/Battman: $(OBJECTS) $(POBJECTS) ../Battman.entitlements
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) $(filter %.o,$^) -o $@
	$(CODESIGN)../Battman.entitlements $@
build/Payload/Battman.app/Info.plist: Info.plist
	@mkdir -p $(@D)
	$(SED) 's/\$$(CURRENT_PROJECT_VERSION)/$(BATTMAN_VERSION)/;s/\$$(MARKETING_VERSION)/$(BATTMAN_VERSION)/;s/\$$(DEVELOPMENT_LANGUAGE)/en/;s/\$$(EXECUTABLE_NAME)/Battman/;s/\$$(PRODUCT_BUNDLE_IDENTIFIER)/com.torrekie.Battman/;s/\$$(PRODUCT_NAME)/Battman/;s/\$$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/;s/\$$(COMMIT_HASH)/$(COMMIT_HASH)/' Info.plist > build/Payload/Battman.app/Info.plist
ifneq (${RELEASE},1)
	$(SED) -i 's/CFBundleIcons/CFBundleIconsDISABLED/' $@
endif

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

build/Battman.ipa: build/Payload/Battman.app/Battman build/Payload/Battman.app/Info.plist ${ICON_IF_RELEASE} build/Payload/Battman.app/license.html build/Payload/Battman.app/BattmanIcons@2x.artwork build/Payload/Battman.app/BattmanIcons@3x.artwork
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
