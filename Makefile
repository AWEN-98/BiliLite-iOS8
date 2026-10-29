export TARGET = iphone:clang:10.3:8.0
export ARCHS = armv7
# Supply per-app Keychain entitlement to ldid on rootful iOS 8.
TARGET_CODESIGN_FLAGS = -S$(CURDIR)/entitlements.plist
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = BiliLite
BiliLite_FILES = main.m
BiliLite_FRAMEWORKS = UIKit Foundation AVFoundation Security CoreImage SystemConfiguration
BiliLite_CFLAGS = -fobjc-arc -Wall -Wno-unused-parameter
BiliLite_LDFLAGS = -Wl,-U,_objc_msgSend_stret
BiliLite_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
