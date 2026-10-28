export TARGET = iphone:clang:10.3:8.0
export ARCHS = armv7
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = BiliLite
BiliLite_FILES = main.m
BiliLite_FRAMEWORKS = UIKit Foundation MediaPlayer
BiliLite_CFLAGS = -fobjc-arc -Wall -Wno-unused-parameter
BiliLite_LDFLAGS = -Wl,-U,_objc_msgSend_stret
BiliLite_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
