#!/bin/zsh
set -euo pipefail

APP_NAME="CapsAwake"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_APP_BUNDLE="${1:-$ROOT_DIR/dist/$APP_NAME.app}"

# Read from the plist rather than retyped, so there is one place the identifier
# changes. It has to agree with AppIdentity.swift and the launchd plists, and the
# daemon is signed with it explicitly — left alone, codesign would derive the
# daemon's identifier from its file name, which the app's code signing
# requirement cannot rely on.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT_DIR/resources/Info.plist")"
DAEMON_LABEL="$BUNDLE_ID.daemon"
# The daemon's *signing* identifier, which is not the launchd label. It has to stay
# what it has always been: launchd records a Lightweight Code Requirement naming it
# when the service is registered, re-registering does not update that requirement, and
# a daemon signed under a new identifier is refused at spawn for good. See
# AppIdentity.daemonSigningIdentifier.
DAEMON_SIGNING_ID="CapsAwakeDaemon"

case "$REQUESTED_APP_BUNDLE" in
  /*) APP_BUNDLE="$REQUESTED_APP_BUNDLE" ;;
  *) APP_BUNDLE="$ROOT_DIR/$REQUESTED_APP_BUNDLE" ;;
esac

if [[ "$APP_BUNDLE" != *.app ]]; then
  echo "Output path must end with .app: $APP_BUNDLE" >&2
  exit 64
fi

cd "$ROOT_DIR"
# `make build` stamps the SDK version. `swift build` alone does not.
make build

# Assemble somewhere else and move into place at the very end. Building in place
# meant that a failure part way through left an unsigned bundle sitting at the
# output path, which launches and then misbehaves in ways that look unrelated.
STAGE="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$STAGE"' EXIT

APP_BUNDLE_FINAL="$APP_BUNDLE"
APP_BUNDLE="$STAGE/$(basename "$APP_BUNDLE_FINAL")"

CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$MACOS" "$RESOURCES" "$LAUNCH_DAEMONS"

/usr/bin/install -m 0755 ".build/release/$APP_NAME" "$MACOS/$APP_NAME"
/usr/bin/install -m 0755 ".build/release/CapsAwakeDaemon" "$MACOS/CapsAwakeDaemon"
/usr/bin/install -m 0644 "$ROOT_DIR/resources/Info.plist" "$CONTENTS/Info.plist"
/usr/bin/install -m 0644 "$ROOT_DIR/resources/CapsAwake.icns" "$RESOURCES/CapsAwake.icns"
/usr/bin/install -m 0644 "$ROOT_DIR/resources/PrivacyInfo.xcprivacy" \
  "$RESOURCES/PrivacyInfo.xcprivacy"
/usr/bin/install -m 0644 "$ROOT_DIR/resources/$DAEMON_LABEL.plist" \
  "$LAUNCH_DAEMONS/$DAEMON_LABEL.plist"

# Localizations live in the app bundle rather than an SPM resource bundle, so
# `Bundle.main` resolves them. SwiftPM's `Bundle.module` would otherwise fall
# back to an absolute path inside .build.
#
# xcstringstool ships with Xcode, not with the Command Line Tools, so say what is
# missing here rather than dying halfway through assembling a bundle.
if ! /usr/bin/xcrun --find xcstringstool >/dev/null 2>&1; then
  cat >&2 <<'MISSING'
Cannot find xcstringstool, which compiles the app's localizations.

It comes with Xcode rather than the Command Line Tools. Install Xcode, then point
the toolchain at it:

  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
MISSING
  exit 69
fi
/usr/bin/xcrun xcstringstool compile --output-directory "$RESOURCES" \
  "$ROOT_DIR/resources/Localizable.xcstrings"

# Developer ID only. A sandboxed App Store build cannot reach the privileged
# daemon at all — macOS denies the mach-lookup — so there is no App Store path
# here to keep working.
if [[ "${SKIP_SIGNING:-}" == "true" ]]; then
  # An ad-hoc signature pins the designated requirement to the code hash, so
  # macOS drops the Accessibility grant on every rebuild. Any real identity keys
  # it to the bundle identifier plus certificate instead, which survives rebuilds.
  IDENTITY="-"
  if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    IDENTITY="$SIGNING_IDENTITY"
  else
    AVAILABLE="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
    for candidate in "${DEV_CERT_NAME:-CapsAwake Dev}" "Apple Development"; do
      if print -r -- "$AVAILABLE" | grep -q "$candidate"; then
        IDENTITY="$candidate"
        break
      fi
    done
  fi
  /usr/bin/codesign --force --sign "$IDENTITY" --identifier "$DAEMON_SIGNING_ID" \
    --timestamp=none "$MACOS/CapsAwakeDaemon"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$APP_BUNDLE"
  echo "Development signing identity: $IDENTITY" >&2
else
  IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
  if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "No signing identity matching \"$IDENTITY\". Set SIGNING_IDENTITY, or pass SKIP_SIGNING=true for a development build." >&2
    exit 70
  fi
  /usr/bin/codesign --force --options runtime --sign "$IDENTITY" \
    --identifier "$DAEMON_SIGNING_ID" "$MACOS/CapsAwakeDaemon"
  /usr/bin/codesign --force --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
fi

# SMAppService rejects a daemon whose bundle does not validate, so catch that here
# rather than letting it surface later as an unexplained registration failure.
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

/bin/rm -rf "$APP_BUNDLE_FINAL"
/bin/mkdir -p "$(dirname "$APP_BUNDLE_FINAL")"
/bin/mv "$APP_BUNDLE" "$APP_BUNDLE_FINAL"

echo "$APP_BUNDLE_FINAL"
