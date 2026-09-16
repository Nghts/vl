ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	TARGET := iphone:clang:latest:15.0
	ARCHS := arm64 arm64e
else
	TARGET := iphone:clang:latest:14.0
endif

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VolumeBoostAll

VolumeBoostAll_FILES = Tweak.x VBVolumeHUD.m VBSettingsPanel.m
VolumeBoostAll_CFLAGS = -fobjc-arc
VolumeBoostAll_FRAMEWORKS = UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
