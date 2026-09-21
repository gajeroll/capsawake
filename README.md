# CapsAwake

[日本語](README.ja.md)

[![CI](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml/badge.svg)](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CapsAwake is a lightweight macOS menu bar app that turns **Caps Lock** into a sleep prevention switch:

- **Caps Lock on** disables system sleep, even with the lid closed and no external display.
- **Caps Lock off** restores normal sleep behavior.
- The menu icon turns green while sleep is prevented; a filled glyph indicates capital letters.

No telemetry, no network requests. English and Japanese UI.

![CapsAwake menu](docs/menu.png)

## Requirements

- **Platform:** macOS 14.0 or later
- **Architecture:** Apple silicon only (Intel is not supported; release builds are not Universal)
- **Build (source only):** Swift 6.2 (Xcode 26)

## Installation

### Prebuilt binary

Download `CapsAwake-<version>.zip` from [Releases](https://github.com/gajeroll/capsawake/releases), unzip it, and drag `CapsAwake.app` to `/Applications`.

On first launch, approve the background daemon under **System Settings → General → Login Items & Extensions**.

### Build from source

```sh
git clone https://github.com/gajeroll/capsawake.git
cd capsawake
make build
make test
SKIP_SIGNING=true ./scripts/build-app.sh ~/Applications/CapsAwake.app
open ~/Applications/CapsAwake.app
```

Source builds run the menu and key actions, but cannot change sleep settings because `launchd` only starts the daemon from a notarized Developer ID build. Use a prebuilt [release](https://github.com/gajeroll/capsawake/releases) or `make notarize`. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Uninstallation

```sh
scripts/uninstall.sh
```

Deleting the app directly leaves the daemon's Login Items record behind. The script quits CapsAwake, restores sleep settings, and unregisters the daemon.

## Permissions

- **Background daemon (root):** Required. `pmset -a disablesleep` is the only public way to keep a Mac awake with the lid closed and no external display. Registered via `SMAppService`. Details in [SECURITY.md](SECURITY.md).
- **Accessibility:** Required only when **Dedicate Caps Lock to CapsAwake** is turned on. When off, CapsAwake reads the hardware state without installing an event tap. Keystrokes are never stored or sent.

## Key Behavior

- **Dedicate Caps Lock to CapsAwake off (default):** A single press types capitals and toggles sleep prevention together.
- **Dedicate Caps Lock to CapsAwake on:**
  - **Caps Lock** alone toggles sleep prevention and does not type capitals.
  - **Shift+Caps Lock** (or a combination recorded in Settings) toggles capitals.
- **Lid closed:** The Mac keeps working without an external display, and the built-in screen is asked to sleep.
- **Energy Mode:** Switches mode while sleep prevention is on (Low Power by default) and restores the previous mode when turned off.
- **Safety shutoff:** Automatically stops sleep prevention on critical heat or below **Minimum battery level** (5% by default).

## Troubleshooting

- **Sleep prevention does not turn on:** Open **System Settings → General → Login Items & Extensions** and enable the CapsAwake daemon.
- **Accessibility permission lost after rebuild:** Toggle CapsAwake off and on under **System Settings → Privacy & Security → Accessibility**, or sign with an Apple Development identity.
- **macOS blocked opening the downloaded app:** Right-click `CapsAwake.app` and choose **Open**.

## Development

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for signing, notarization, and release workflows.

```sh
make build
make test
make lint
```

## Security

The daemon runs as root. See [SECURITY.md](SECURITY.md) for supported operations and vulnerability reporting.

## Credits

Inspired by [Capsomnia](https://github.com/fuji-mak/Capsomnia).

## License

Distributed under the [MIT License](LICENSE).
