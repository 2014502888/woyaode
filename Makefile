export THEOS ?= $(THEOS)
# 不写死 SDK 版本, 用 runner 上 Xcode 默认 SDK(避免 iPhoneOS15.0.sdk 不存在)
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = gaixx

# 改xx - 消息文字修改
gaixx_FILES = Tweak.x
gaixx_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-error
gaixx_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS)/makefiles/tweak.mk
