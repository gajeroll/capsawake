# Local release configuration (template)
#
# Usage:
#   cp config/release.example.mk config/release.mk
#   # Fill in the Team ID, Issuer ID, and the rest
#   make release-check
#
# config/release.mk is not committed.

APPLE_TEAM_ID :=
RELEASE_BUNDLE_ID := com.gajeroll.capsawake

# App Store Connect API key, used for notarization
ASC_KEY_ID :=
ASC_ISSUER_ID :=
ASC_KEY_PATH := $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8

# Signing identity in the keychain. A substring is enough.
# Confirm with `security find-identity -v -p codesigning`.
DEV_ID_SIGNING_IDENTITY := Developer ID Application

# Output directory
RELEASE_DIST_DIR := dist/release
