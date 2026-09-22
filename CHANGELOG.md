# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
version lives in `resources/Info.plist`; releases are tagged `vX.Y.Z`.

## [Unreleased]

### Fixed
- Record the SDK version at link time so Settings keeps the current macOS interface.

## [1.0.0] - 2026-09-22

### Added
- Initial public release of CapsAwake.
- Caps Lock as a physical keep-awake switch to prevent system sleep with lid closed.
- Privileged root daemon over XPC with mutual code-signing verification and no sudoers requirements.
- Energy Mode switching (Low Power, Automatic, High Power) while sleep prevention is active.
- Onboarding flow and preferences interface built with SwiftUI.
- Full English and Japanese localizations.
- Zero telemetry, analytics, network calls, or account requirements.

[Unreleased]: https://github.com/gajeroll/capsawake/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/gajeroll/capsawake/releases/tag/v1.0.0
