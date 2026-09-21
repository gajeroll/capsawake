# CapsAwake

[日本語](README.ja.md)

[![CI](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml/badge.svg)](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CapsAwake is a macOS menu bar app that turns **Caps Lock** into a keep-awake switch.

- **Caps Lock on** disables system sleep, including with the lid closed and no external display.
- **Caps Lock off** restores normal sleep.
- The menu bar icon is green while sleep is being prevented.

It does not collect telemetry or make network requests. The interface follows your system language, or the language you pick in Settings.

![CapsAwake menu](docs/menu.png)

## Requirements

- macOS 14 or later
- Apple silicon. Release builds are not Universal, and Intel Macs are not supported.

## Installation

### Prebuilt binary

Download `CapsAwake-<version>.zip` from
[Releases](https://github.com/gajeroll/capsawake/releases), unzip it, and move
`CapsAwake.app` to `/Applications`.

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

Needs macOS 14 or later and Swift 6.2 (Xcode 26). A source build runs the menu
and the key, but it cannot change the sleep setting: the daemon only starts
from a notarized Developer ID build. Use a
[release](https://github.com/gajeroll/capsawake/releases) or `make notarize`.
Details are in [CONTRIBUTING.md](CONTRIBUTING.md).

### Uninstallation

```sh
scripts/uninstall.sh
```

Moving the app to the Trash leaves the daemon's Login Items record behind. The
script quits CapsAwake, restores the sleep setting it changed, and unregisters
the daemon.

## Permissions

- **Background daemon (root).** Required. `pmset -a disablesleep` is the only
  public way to keep a Mac awake with the lid closed and no external display.
  The daemon is registered with `SMAppService`.
  [SECURITY.md](SECURITY.md) lists exactly what it will do.
- **Accessibility.** Required only after you turn on **Dedicate Caps Lock to
  CapsAwake**. Until then CapsAwake reads the hardware lock and does not
  install an event tap. Keystrokes are never stored or sent anywhere.

## The key

With **Dedicate Caps Lock to CapsAwake** off, one press types capitals and
toggles sleep prevention together.

Turn it on and the two split:

- Caps Lock alone toggles sleep prevention and does not type capitals.
- **Shift+Caps Lock**, or a combination you record in Settings, toggles capitals.
- Green means sleep prevention. A filled glyph means capitals are on.

Closing the lid keeps the Mac working without an external display, and the
built-in screen is asked to sleep. While sleep prevention is on, CapsAwake can
switch Energy Mode (Low Power by default) and restores the previous mode when
it turns off.

Sleep prevention stops on its own if the Mac reports critical heat, or if the
battery falls below **Minimum battery level** in Settings (5% by default).

## Troubleshooting

- **Sleep prevention never turns on.** Open **System Settings → General → Login
  Items & Extensions** and enable the CapsAwake daemon.
- **Accessibility disappeared after a rebuild.** An ad-hoc signature changes
  every build, so macOS drops the grant. Sign with an Apple Development
  identity, or toggle CapsAwake off and on under **Privacy & Security →
  Accessibility**.
- **macOS refuses to open the downloaded app.** Right-click `CapsAwake.app` and
  choose **Open**.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for signing, notarization, and releases.

```sh
make build
make test
make lint
```

## Security

The daemon runs as root. [SECURITY.md](SECURITY.md) lists the requests it
accepts and how to report a vulnerability.

## Credits

Inspired by [Capsomnia](https://github.com/fuji-mak/Capsomnia).

## License

[MIT](LICENSE)
