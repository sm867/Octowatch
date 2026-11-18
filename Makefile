
APP_NAME := Octowatch
APP_BUNDLE := $(APP_NAME).app

# Command Line Tools alone ship no SwiftUIMacros plugin for the macOS 27 SDK; use 26.5 instead.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk),)
export SDKROOT := /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
endif
endif

BIN_PATH := $(shell swift build -c release --show-bin-path 2>/dev/null)

.PHONY: build release bundle run open clean

## Development build
build:
	swift build

## Release build
release:
	$(MAKE) clean && $(MAKE) bundle && swift build -c release

## Build .app bundle (release)
bundle:
	bash Scripts/bundle.sh

## Build bundle and launch the app
run: bundle
	open $(APP_BUNDLE)

## Open an existing bundle (no rebuild)
open:
	open $(APP_BUNDLE)

## Remove build artifacts and app bundle
clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
