# Distribution

This document outlines distribution constraints and the planned release pipeline. Developer ID notarization is currently implemented; Homebrew Cask and Sparkle updates are planned for future stages.

## Why the Mac App Store is unsupported

CapsAwake cannot be distributed via the Mac App Store due to mandatory App Sandbox restrictions:

- `pmset -a disablesleep` requires root privileges. It is the only public mechanism to prevent sleep when a MacBook lid is closed without an external display. Standard `IOPMAssertion` calls are ignored by macOS when the lid is closed.
- Sandboxed applications cannot establish XPC connections to privileged daemons (`deny(1) mach-lookup com.gajeroll.capsawake.daemon`).
- Sandboxed processes cannot execute `/usr/bin/pmset` or `/usr/bin/hidutil`.
- `IOServiceOpen` on `IOHIDSystem` with `kIOHIDParamConnectType` (used to read and write Caps Lock LED state) is denied under App Sandbox.
- Intercepting Caps Lock via an event tap requires Accessibility / Input Monitoring permissions not permitted in Mac App Store sandboxes.

Consequently, direct distribution with Developer ID signing and Apple notarization is the only supported packaging path.

## Current release build

`make notarize` builds the application using a Developer ID identity, submits the archive to Apple's notary service, staples the notarization ticket, and writes `CapsAwake-notarized.zip` to `dist/release/`.

## Planned Stage 1 — Homebrew Cask

Homebrew Cask provides a standard distribution channel for command-line users:

1. Produce signed and notarized `.dmg` images in `scripts/notarize.sh`.
2. Attach the disk image to GitHub Releases as a tagged asset (`v<version>`).
3. Maintain a Cask formula (initially via a custom tap).

The Cask formula must handle privileged daemon cleanup during uninstallation:
- `quit:` for `com.gajeroll.capsawake`
- `launchctl:` for `com.gajeroll.capsawake.daemon`
- `zap trash:` covering `~/Library/Preferences/com.gajeroll.capsawake.plist` and `/Library/Application Support/CapsAwake/`

## Planned Stage 2 — Sparkle Updater

Sparkle 2 provides in-app updates for non-App Store applications:

1. Add Sparkle package dependency to `Package.swift`.
2. Bundle `Sparkle.framework` inside `Contents/Frameworks/` in `scripts/build-app.sh`.
3. Sign all nested binaries (`Autoupdate`, `Updater.app`, `Sparkle.framework`, `CapsAwakeDaemon`, `CapsAwake.app`) with hardened runtime and Developer ID certificates.
4. Generate EdDSA update signing keys (`generate_keys`), storing `SUPublicEDKey` in `resources/Info.plist`.
5. Host `appcast.xml` over HTTPS (e.g. GitHub Pages or GitHub Releases).
6. Automate the release pipeline: build, notarize, staple, sign update artifact with `sign_update`, generate appcast, and publish.

## Daemon registration lifecycle

`SMAppService` registers the daemon binary present at registration time. When the application is updated in place, `AppController` compares the running build identifier and bundle path against stored registration records and re-registers the daemon when changes are detected. Existing user approvals in Login Items & Extensions are preserved across updates.

## Bundle identifier and signing constraints

The daemon's launchd label (`com.gajeroll.capsawake.daemon`) and signing identifier (`CapsAwakeDaemon`) must remain constant across releases.

When a daemon is registered, launchd creates a Lightweight Code Requirement (LWCR) binding the service to its initial signing identifier and validation authority. If a daemon binary is signed with a different identifier or validation category, launchd refuses to spawn the service (`xpcproxy` exits `EX_CONFIG`), rendering the daemon inoperable until manually unregistered.
