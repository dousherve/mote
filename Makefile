SWIFT ?= swift
XCRUN ?= xcrun
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.DEFAULT_GOAL := release

.PHONY: release build test check clean re help

release:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(XCRUN) swift build -c release
	codesign --force --sign - --entitlements Resources/Mote.entitlements .build/release/mote
	@echo "Built and signed .build/release/mote"

build:
	$(SWIFT) build

test:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" $(XCRUN) swift test

check: test

clean:
	$(SWIFT) package clean
	rm -rf .build

re: clean release

help:
	@echo "Mote development targets:"
	@echo "  make release  Build and sign the release executable (default)"
	@echo "  make build    Build a debug executable"
	@echo "  make test     Run the test suite using Xcode's toolchain"
	@echo "  make check    Alias for make test"
	@echo "  make clean    Remove SwiftPM build artifacts"
	@echo "  make re       Clean, then build and sign the release executable"
