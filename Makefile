.PHONY: help build test lint fmt clean app pkg release-check notarize print-release-config

ROOT_DIR := $(CURDIR)
-include config/release.mk

help:
	@echo "CapsAwake"
	@echo ""
	@echo "  Develop"
	@echo "    make build              swift build -c release"
	@echo "    make test               swift test"
	@echo "    make lint               check formatting (what CI runs)"
	@echo "    make fmt                reformat Sources and Tests in place"
	@echo "    make clean              remove .build and dist"
	@echo ""
	@echo "  Package"
	@echo "    make app                build a development .app into dist/"
	@echo "    make pkg                build a development .pkg into dist/"
	@echo ""
	@echo "  Release (needs config/release.mk)"
	@echo "    make release-check      verify certificates, API key and settings"
	@echo "    make notarize           Developer ID build, notarized and stapled"
	@echo ""
	@echo "First time: cp config/release.example.mk config/release.mk"

# SwiftPM writes the deployment target into the SDK version field, so macOS keeps
# the pre-Liquid Glass interface. 14.0 matches platforms in Package.swift.
MACOS_DEPLOYMENT_TARGET := 14.0
MACOS_SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)

build:
	swift build -c release \
		-Xlinker -platform_version -Xlinker macos \
		-Xlinker $(MACOS_DEPLOYMENT_TARGET) -Xlinker $(MACOS_SDK_VERSION)

test:
	swift test

# --strict is what makes this fail. Without it every finding is a warning and the
# command exits 0, so a repository full of violations looks clean.
lint:
	swift format lint --strict --recursive Sources Tests

fmt:
	swift format format --in-place --recursive Sources Tests

clean:
	rm -rf .build dist

app:
	SKIP_SIGNING=true ./scripts/build-app.sh dist/CapsAwake.app

pkg:
	SKIP_SIGNING=true ./scripts/build-pkg.sh dist/CapsAwake.pkg

release-check:
	@eval "$$($(MAKE) -s print-release-config)" && ./scripts/release-check.sh

print-release-config:
	@echo 'export APPLE_TEAM_ID="$(APPLE_TEAM_ID)"'
	@echo 'export RELEASE_BUNDLE_ID="$(RELEASE_BUNDLE_ID)"'
	@echo 'export ASC_KEY_ID="$(ASC_KEY_ID)"'
	@echo 'export ASC_ISSUER_ID="$(ASC_ISSUER_ID)"'
	@echo 'export ASC_KEY_PATH="$(ASC_KEY_PATH)"'
	@echo 'export DEV_ID_SIGNING_IDENTITY="$(DEV_ID_SIGNING_IDENTITY)"'
	@echo 'export RELEASE_DIST_DIR="$(RELEASE_DIST_DIR)"'

notarize:
	@eval "$$($(MAKE) -s print-release-config)" && ./scripts/notarize.sh
