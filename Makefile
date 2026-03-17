BINARY = .build/debug/Vibeshed
ENTITLEMENTS = Vibeshed/Vibeshed.entitlements
BUNDLE_ID = com.ivandmitriev.Vibeshed
APP_NAME = Vibeshed
APP_BUNDLE = .build/$(APP_NAME).app
APP_BINARY = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
SWIFTLINT = .build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint

# Version from git tags: "v0.1.0" → "0.1.0"; fallback "0.1.0-dev"
VERSION := $(shell V=$$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); echo "$${V:-0.1.0-dev}")
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo "1")

.PHONY: build run run-debug clean log lint lint-fix

build:
	swift build
	@# Assemble .app bundle so macOS TCC can track permissions properly
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp $(BINARY) "$(APP_BINARY)"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@# Generate Info.plist with concrete values (resolve Xcode-style variables)
	@sed \
		-e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
		-e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
		-e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
		-e 's/$$(MARKETING_VERSION)/$(VERSION)/g' \
		-e 's/$$(BUILD_VERSION)/$(BUILD_NUMBER)/g' \
		Vibeshed/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"
	@codesign --force --sign "Apple Development: iam@ivandmitriev.com (BDFRA4JH67)" \
		--entitlements $(ENTITLEMENTS) \
		--identifier $(BUNDLE_ID) \
		--options runtime \
		"$(APP_BUNDLE)"

# Launch as .app bundle (required for permissions to work)
run: build
	@-pkill -x $(APP_NAME) 2>/dev/null && sleep 0.5 || true
	@open "$(APP_BUNDLE)"
	@echo "Vibeshed launched — use 'make log' in another terminal for live logs"

# Run the bundle binary directly with stderr output in this terminal
run-debug: build
	@-pkill -x $(APP_NAME) 2>/dev/null && sleep 0.5 || true
	"$(APP_BINARY)"

# Stream all Vibeshed OSLog messages (run in a separate terminal alongside `make run`)
log:
	log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug --style compact

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"

lint:
	$(SWIFTLINT) lint --reporter xcode

lint-fix:
	$(SWIFTLINT) lint --fix --reporter xcode
