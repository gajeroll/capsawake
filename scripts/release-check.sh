#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass() { print -r -- "  ok    $1" }
fail() { print -r -- "  FAIL  $1" >&2; STATUS=1 }
warn() { print -r -- "  warn  $1" >&2 }

STATUS=0

print -r -- "Release environment check"
print -r -- "========================="

if [[ ! -f "$ROOT_DIR/config/release.mk" ]]; then
  fail "config/release.mk is missing"
  print -r -- ""
  print -r -- "Create it with:"
  print -r -- "  cp config/release.example.mk config/release.mk"
  exit 1
fi

check_nonempty() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    pass "$name"
  else
    fail "$name is not set (config/release.mk)"
  fi
}

print -r -- ""
print -r -- "[Settings]"
check_nonempty "APPLE_TEAM_ID" "${APPLE_TEAM_ID:-}"
check_nonempty "RELEASE_BUNDLE_ID" "${RELEASE_BUNDLE_ID:-}"
check_nonempty "ASC_KEY_ID" "${ASC_KEY_ID:-}"
check_nonempty "ASC_ISSUER_ID" "${ASC_ISSUER_ID:-}"

print -r -- ""
print -r -- "[App Store Connect API key]"
if [[ -f "${ASC_KEY_PATH:-}" ]]; then
  pass "API key: ${ASC_KEY_PATH}"
else
  fail "API key not found: ${ASC_KEY_PATH:-(not set)}"
fi

print -r -- ""
print -r -- "[Signing certificate]"
IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"

DEV_ID_PATTERN="${DEV_ID_SIGNING_IDENTITY:-Developer ID Application}"
if print -r -- "$IDENTITIES" | grep -qF -- "$DEV_ID_PATTERN"; then
  pass "Developer ID, for direct distribution and notarization ($DEV_ID_PATTERN)"
else
  fail "No Developer ID in the keychain ($DEV_ID_PATTERN)"
  print -r -- "        Create one in the Developer Portal and double-click the .cer to install it" >&2
fi

print -r -- ""
print -r -- "[Tools]"
for tool in notarytool codesign stapler; do
  if /usr/bin/xcrun --find "$tool" >/dev/null 2>&1; then
    pass "xcrun $tool"
  else
    fail "xcrun $tool not found"
  fi
done

print -r -- ""
print -r -- "[Identity]"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  CURRENT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$CURRENT_BUNDLE_ID" == "${RELEASE_BUNDLE_ID:-}" ]]; then
    pass "Info.plist bundle ID matches RELEASE_BUNDLE_ID ($CURRENT_BUNDLE_ID)"
  else
    warn "Info.plist ($CURRENT_BUNDLE_ID) and RELEASE_BUNDLE_ID (${RELEASE_BUNDLE_ID:-not set}) disagree"
  fi
else
  fail "resources/Info.plist not found"
fi

# Official releases document this team. A running app does not trust the constant:
# it reads the team from its own signature, so a fork signed by another team still
# works. The check below only confirms a release is configured for the team the
# source says it ships under.
SOURCE_TEAM_ID="$(grep -o 'teamIdentifier = "[^"]*"' "$ROOT_DIR/Sources/CapsAwakeCore/AppIdentity.swift" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [[ -z "$SOURCE_TEAM_ID" ]]; then
  fail "Could not read teamIdentifier from Sources/CapsAwakeCore/AppIdentity.swift"
elif [[ "$SOURCE_TEAM_ID" == "${APPLE_TEAM_ID:-}" ]]; then
  pass "AppIdentity.teamIdentifier matches APPLE_TEAM_ID ($SOURCE_TEAM_ID)"
else
  fail "AppIdentity.teamIdentifier ($SOURCE_TEAM_ID) and APPLE_TEAM_ID (${APPLE_TEAM_ID:-not set}) disagree"
  print -r -- "        The app and its daemon check each other's team; a release signed by another" >&2
  print -r -- "        team would install and then be unable to change any sleep setting." >&2
fi

if print -r -- "$IDENTITIES" | grep -qF -- "$DEV_ID_PATTERN"; then
  if ! print -r -- "$IDENTITIES" | grep -F -- "$DEV_ID_PATTERN" | grep -qF -- "(${APPLE_TEAM_ID:-})"; then
    warn "The Developer ID in the keychain does not carry team ${APPLE_TEAM_ID:-not set}"
  fi
fi

print -r -- ""
if [[ "$STATUS" -eq 0 ]]; then
  print -r -- "All good."
else
  print -r -- "Something is unfinished — fix the above and run again."
fi

exit "$STATUS"
