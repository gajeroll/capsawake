#!/bin/zsh
set -euo pipefail

# Removes CapsAwake completely: the app, the daemon launchd was told about, and the
# state the daemon keeps as root.
#
# Deleting the app bundle on its own is not enough. Registering the daemon leaves a
# record in Background Task Management that survives the app, so it goes on appearing
# in Login Items & Extensions, and the baseline the daemon keeps lives in
# /Library/Application Support, which only root can remove.

APP_NAME="CapsAwake"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"

if [[ -f "$INFO_PLIST" ]]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
else
  BUNDLE_ID="com.gajeroll.capsawake"
fi
DAEMON_LABEL="$BUNDLE_ID.daemon"
SUPPORT_DIR="/Library/Application Support/$APP_NAME"

print -r -- "Uninstalling $APP_NAME"
print -r -- ""

# Quitting first is not just tidiness: on the way out the app puts back the sleep
# setting, the Energy Mode and the Caps Lock key delay it borrowed. Killing it
# outright would leave all three where CapsAwake had them.
if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  print -r -- "Quitting $APP_NAME so it can put your settings back..."
  /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || \
    /usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
  for _ in {1..20}; do
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.5
  done
  /usr/bin/pkill -9 -x "$APP_NAME" 2>/dev/null || true
fi

for candidate in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
  if [[ -d "$candidate" ]]; then
    print -r -- "Removing $candidate"
    /bin/rm -rf "$candidate"
  fi
done

print -r -- ""
print -r -- "The rest needs administrator rights: unregistering the background daemon,"
print -r -- "making sure sleep is enabled again, and removing its saved state."
print -r -- ""

/usr/bin/sudo /bin/sh -s "$DAEMON_LABEL" "$SUPPORT_DIR" <<'PRIVILEGED'
set -eu
DAEMON_LABEL="$1"
SUPPORT_DIR="$2"

# The registration outlives the app bundle, so it is torn down by label.
launchctl bootout "system/$DAEMON_LABEL" 2>/dev/null || true
launchctl disable "system/$DAEMON_LABEL" 2>/dev/null || true

# Only ever turn sleep back on. If the machine still says sleep is disabled, that is
# either ours to undo or something the owner set; either way a Mac that sleeps is the
# safe end to leave an uninstall on.
if /usr/bin/pmset -g | grep -q 'SleepDisabled.*1'; then
  echo "Re-enabling sleep"
  /usr/bin/pmset -a disablesleep 0 || true
fi

case "$SUPPORT_DIR" in
  /Library/Application\ Support/*)
    if [ -d "$SUPPORT_DIR" ]; then
      echo "Removing $SUPPORT_DIR"
      rm -rf "$SUPPORT_DIR"
    fi
    ;;
  *)
    echo "Refusing to remove an unexpected path: $SUPPORT_DIR" >&2
    ;;
esac
PRIVILEGED

print -r -- ""
print -r -- "Removing preferences"
# By path, not by domain. `defaults delete com.gajeroll.capsawake` resolves the name
# against a sandbox container that CapsAwake does not have and quietly fails, leaving
# the real file — and with it the record of which daemon build was registered, which
# is enough to stop a reinstalled app from registering one at all.
/bin/rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
/usr/bin/defaults delete "$BUNDLE_ID" 2>/dev/null || true
# cfprefsd caches the domain, so a reinstall would otherwise read back what was just
# deleted.
/usr/bin/killall -u "$USER" cfprefsd 2>/dev/null || true

print -r -- ""
print -r -- "Done. The Caps Lock key delay, if CapsAwake had removed it, is an I/O"
print -r -- "registry override and is already back — it does not survive a restart."
