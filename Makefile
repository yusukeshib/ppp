APP = ppp.app
BIN = .build/release/ppp
# Keep a stable signature so Accessibility permission survives local rebuilds.
# Distribution builds override this with a Developer ID Application identity.
SIGN_IDENTITY ?= Apple Development: Yusuke Shibata (6F8N535B8W)
BUNDLE_IDENTIFIER ?= dev.yusukeshib.ppp.dev
BUNDLE_NAME ?= ppp Dev
# Distribution builds enable Hardened Runtime and a secure timestamp.
CODESIGN_FLAGS ?=
RUN_ARGS ?=

.PHONY: all build bundle run release clean icon

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_IDENTIFIER)" $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleName $(BUNDLE_NAME)" $(APP)/Contents/Info.plist
	cp $(BIN) $(APP)/Contents/MacOS/
	cp Assets/ppp.icns $(APP)/Contents/Resources/
	cp -R Resources/*.lproj $(APP)/Contents/Resources/
	codesign --force $(CODESIGN_FLAGS) --sign "$(SIGN_IDENTITY)" $(APP)

run: bundle
	@pkill -x ppp 2>/dev/null || true
	@if [ -n "$(RUN_ARGS)" ]; then \
		open $(APP) --args $(RUN_ARGS); \
	else \
		open $(APP); \
	fi

icon:
	swift Scripts/generate-icon.swift Assets/pppIcon.png
	rm -rf .build/ppp.iconset
	mkdir -p .build/ppp.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s Assets/pppIcon.png --out .build/ppp.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s * 2)); \
		sips -z $$d $$d Assets/pppIcon.png --out .build/ppp.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns .build/ppp.iconset -o Assets/ppp.icns
	rm -rf .build/ppp.iconset

release:
	./Scripts/release.sh

clean:
	swift package clean
	rm -rf $(APP) ppp.dmg
