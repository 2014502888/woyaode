export THEOS ?= $(THEOS)
# 不写死 SDK 版本, 用 runner 上 Xcode 默认 SDK(避免 iPhoneOS15.0.sdk 不存在)
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MisakaJokerTweak

# 反推自 2.dylib: Misaka(会话分组) + Joker(消息小丑恶搞)
MisakaJokerTweak_FILES = Tweak.x
MisakaJokerTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-error
MisakaJokerTweak_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS)/makefiles/tweak.mk
