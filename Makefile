SWIFT ?= swift
XCRUN ?= xcrun
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.DEFAULT_GOAL := build

.PHONY: build release test check clean help

build:
	$(SWIFT) build

release:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(XCRUN) swift build -c release
	codesign --force --sign - --entitlements Resources/Mote.entitlements .build/release/mote
	@echo "Built and signed .build/release/mote"

test:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(XCRUN) swift test

check: test

clean:
	$(SWIFT) package clean
	rm -rf .build

help:
	@echo "Mote development targets:"
	@echo "  make build    Build a debug executable (default)"
	@echo "  make release  Build and sign the release executable"
	@echo "  make test     Run the test suite using Xcode's toolchain"
	@echo "  make check    Alias for make test"
	@echo "  make clean    Remove SwiftPM build artifacts"
