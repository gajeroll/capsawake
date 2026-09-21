#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CapsAwake"

require_var() {
  if [[ -z "${(P)1:-}" ]]; then
    print -r -- "Missing $1 (config/release.mk)" >&2
    exit 1
  fi
}

require_var RELEASE_DIST_DIR
require_var DEV_ID_SIGNING_IDENTITY
require_var ASC_KEY_ID
require_var ASC_ISSUER_ID
require_var ASC_KEY_PATH

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  print -r -- "API key not found: $ASC_KEY_PATH" >&2
  exit 1
fi

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
if ! print -r -- "$IDENTITIES" | grep -q "$DEV_ID_SIGNING_IDENTITY"; then
  print -r -- "No signing identity matching \"$DEV_ID_SIGNING_IDENTITY\"" >&2
  exit 1
fi

case "$RELEASE_DIST_DIR" in
  /*) DIST_DIR="$RELEASE_DIST_DIR" ;;
  *) DIST_DIR="$ROOT_DIR/$RELEASE_DIST_DIR" ;;
esac

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SUBMIT_ZIP="$DIST_DIR/$APP_NAME-submit.zip"
DIST_ZIP="$DIST_DIR/$APP_NAME-notarized.zip"

/bin/mkdir -p "$DIST_DIR"

print -r -- "Building signed app..."
SIGNING_IDENTITY="$DEV_ID_SIGNING_IDENTITY" "$ROOT_DIR/scripts/build-app.sh" "$APP_BUNDLE"

print -r -- "Creating submission archive..."
/bin/rm -f "$SUBMIT_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$SUBMIT_ZIP"

print -r -- "Submitting to Apple notary service..."
/usr/bin/xcrun notarytool submit "$SUBMIT_ZIP" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

print -r -- "Stapling notarization ticket..."
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"

# Ask Gatekeeper the question the user's Mac will ask. Notarizing and stapling can
# both succeed and still leave something that will not open — a nested piece signed
# with the wrong identity, say — and the first person to find out should not be
# whoever downloads it.
print -r -- "Asking Gatekeeper whether it will open..."
/usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE"

print -r -- "Creating distribution archive..."
/bin/rm -f "$DIST_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"

print -r -- ""
print -r -- "Notarization complete:"
print -r -- "  App:  $APP_BUNDLE"
print -r -- "  Zip:  $DIST_ZIP"
