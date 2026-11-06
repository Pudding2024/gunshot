TARGET := iphone:clang:latest:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
include ../sources.mk
LIBRARY_NAME = GunshotJailed
GunshotJailed_FILES = Hooks.m EmbeddedService.m SideloadKeychain.m SideloadIdentity.m $(addprefix ../,$(filter-out Native/GSNativeRelay.m,$(GUNSHOT_HOST_FILES)))
GunshotJailed_CFLAGS = -fobjc-arc -DGS_JAILED=1 -I../Shared -I../.build
GunshotJailed_FRAMEWORKS = UIKit Foundation CoreGraphics Photos PhotosUI Network Security CoreFoundation LocalAuthentication UniformTypeIdentifiers
GunshotJailed_LIBRARIES = resolv
GunshotJailed_LDFLAGS = $(THEOS_PROJECT_DIR)/../.build/libgotohp.a -Wl,-install_name,@rpath/GunshotJailed.dylib
GunshotJailed_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
include $(THEOS_MAKE_PATH)/library.mk
before-all::
	@test -f ../.build/libgotohp.a || (echo 'Run scripts/build-go.sh first'; exit 1)
after-stage::
	cp ../Gunshot.plist "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/GunshotJailed.plist"
	mkdir -p "$(THEOS_STAGING_DIR)/Library/Frameworks"
	cp -R ../.build/CydiaSubstrate.framework "$(THEOS_STAGING_DIR)/Library/Frameworks/"

	mkdir -p "$(THEOS_STAGING_DIR)/usr/share/doc/dev.tqmane.gunshot.jailed"
	cp ../.build/ThirdPartyNotices.txt "$(THEOS_STAGING_DIR)/usr/share/doc/dev.tqmane.gunshot.jailed/"
