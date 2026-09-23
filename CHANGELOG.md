# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
version lives in `resources/Info.plist`; releases are tagged `vX.Y.Z`.

## [Unreleased]

## [0.1.0] - 2026-09-23

### Added
- Initial public release of CapsAwake.
- Caps Lock as a physical keep-awake switch to prevent system sleep with lid closed.
- Privileged root daemon over XPC with mutual code-signing verification and no sudoers requirements.
- Energy Mode switching (Low Power, Automatic, High Power) while sleep prevention is active.
- Onboarding flow and preferences interface built with SwiftUI.
- Full English and Japanese localizations.
- Zero telemetry, analytics, network calls, or account requirements.

[Unreleased]: https://github.com/gajeroll/capsawake/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gajeroll/capsawake/releases/tag/v0.1.0
