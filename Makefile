TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VolumeBoostAll
VolumeBoostAll_FILES = Tweak.x VBVolumeHUD.m
VolumeBoostAll_CFLAGS = -fobjc-arc
VolumeBoostAll_FRAMEWORKS = UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
