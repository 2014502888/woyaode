export THEOS ?= $(THEOS)
TARGET := iphone:clang:15.0:15.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MisakaJokerTweak

# 反推自 2.dylib: Misaka(会话分组) + Joker(消息小丑恶搞)
MisakaJokerTweak_FILES = Tweak.x
MisakaJokerTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
MisakaJokerTweak_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS)/makefiles/tweak.mk
