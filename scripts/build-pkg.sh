#!/bin/zsh
set -euo pipefail

APP_NAME="CapsAwake"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT_DIR/dist/$APP_NAME.pkg}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"

# Read from the plist rather than retyped here. The version used to be written in
# both places and only one of them ever got updated.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

mkdir -p "$(dirname "$OUTPUT")"
# SKIP_SIGNING carries through, so `SKIP_SIGNING=true` here produces a development
# package rather than failing on a missing Developer ID halfway down.
"$ROOT_DIR/scripts/build-app.sh" "$APP_BUNDLE"

PAYLOAD="$(mktemp -d)"
trap 'rm -rf "$PAYLOAD"' EXIT
mkdir -p "$PAYLOAD/Applications"
/usr/bin/ditto "$APP_BUNDLE" "$PAYLOAD/Applications/$APP_NAME.app"

/usr/bin/pkgbuild \
  --root "$PAYLOAD" \
  --identifier "$BUNDLE_ID.pkg" \
  --version "$VERSION" \
  --install-location "/" \
  "$OUTPUT"

echo "Built $OUTPUT ($VERSION)"

# This package installs an app that registers a root daemon, and pkgbuild does not
# sign the installer itself. Say so rather than leaving someone to hand it around.
if [[ "${SKIP_SIGNING:-}" == "true" ]]; then
  cat >&2 <<'WARNING'

  This package is not signed and not notarized. It is for testing on this Mac.
  Do not distribute it: Gatekeeper will refuse it, and it installs an app that
  asks to run a background daemon as root.

WARNING
fi
