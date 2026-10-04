ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = Importone
Importone_FILES = Tweak.xm TonePicker.xm ImportActivity.m Shared/Bridge.m Shared/Validation.m
Importone_CFLAGS = -fobjc-arc
Importone_FRAMEWORKS = UIKit Foundation AVFoundation UniformTypeIdentifiers
Importone_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
TOOL_NAME = importoned
importoned_FILES = Daemon/main.m Shared/Bridge.m Shared/Validation.m
importoned_CFLAGS = -fobjc-arc
importoned_FRAMEWORKS = Foundation AVFoundation
importoned_INSTALL_PATH = /usr/libexec
importoned_CODESIGN_FLAGS = -SDaemon/entitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
BUNDLE_NAME = ImportonePrefs
ImportonePrefs_FILES = Preferences/RootListController.m Preferences/CreditCell.m Shared/Bridge.m Shared/Validation.m
ImportonePrefs_CFLAGS = -fobjc-arc -DIPMessageCenter=IPPreferencesMessageCenter
ImportonePrefs_FRAMEWORKS = UIKit Foundation
ImportonePrefs_PRIVATE_FRAMEWORKS = Preferences
ImportonePrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/Frameworks
ImportonePrefs_INSTALL_PATH = /Library/PreferenceBundles
ImportonePrefs_RESOURCE_DIRS = Preferences/Resources
include $(THEOS_MAKE_PATH)/bundle.mk
