BINARY = .build/debug/Vibeshed
ENTITLEMENTS = Vibeshed/Vibeshed.entitlements
BUNDLE_ID = com.vibeshed.app

.PHONY: build run clean

build:
	swift build
	codesign --force --sign - \
		--entitlements $(ENTITLEMENTS) \
		--identifier $(BUNDLE_ID) \
		$(BINARY)

run: build
	$(BINARY)

clean:
	swift package clean
