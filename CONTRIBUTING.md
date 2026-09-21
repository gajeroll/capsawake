# Contributing

Issues and pull requests are welcome.

## Getting set up

macOS 14 or later and Swift 6.2 (Xcode 26) are required. `xcstringstool`, which compiles localizations, is included with Xcode rather than Command Line Tools.

```sh
git clone https://github.com/gajeroll/capsawake.git
cd capsawake
make build
make test
make lint
```

`make lint` runs the same strict checks as CI. Use `make fmt` to reformat Swift code in place. `make help` lists available targets.

Before modifying code, read [docs/architecture.md](docs/architecture.md) for module boundaries and architectural principles:
- `CapsAwakeCore` imports Foundation only.
- System observations mutate state solely through `Intent`.
- Policy decisions live in `SleepPreventionReducer`.

## Code signing tiers

Development builds support three code-signing tiers:
1. **Apple Development**: Signed with an official development certificate from Keychain Access. Preserves Accessibility permissions across rebuilds.
2. **Self-signed "CapsAwake Dev" certificate**: A local code-signing certificate created in Keychain Access. Also preserves Accessibility permissions across rebuilds.
3. **Ad-hoc signature (`IDENTITY="-"`)**: Used when `SKIP_SIGNING=true`. Identity is keyed to code hash, meaning macOS resets Accessibility grants on every rebuild.

`make app` runs `scripts/build-app.sh` with `SKIP_SIGNING=true` by default for local bundles. Note that sleep prevention itself requires `make notarize` (or a Developer ID signed build); launchd refuses to spawn non-notarized daemons registered with Developer ID launch constraints. Before registering the daemon manually, build a release-signed app.

```sh
make app     # dist/CapsAwake.app (SKIP_SIGNING=true by default)
make pkg     # dist/CapsAwake.pkg — development installer for testing on this Mac only
```

## Trying out sleep prevention

Disabling sleep is performed by `CapsAwakeDaemon`. When registered via `SMAppService`, launchd enforces the launch constraint recorded during registration — requiring a notarized Developer ID binary.

A build straight from `make app` (`SKIP_SIGNING=true`) is not notarized; launchd will refuse to spawn its daemon (`xpcproxy` exits `EX_CONFIG` and `launchctl print system/com.gajeroll.capsawake.daemon` reports `last exit code = 78`). The app runs, but cannot change sleep settings.

To test sleep prevention end-to-end, build with `make notarize` using your own Apple Developer ID credentials. Note that the app and daemon verify each other's Team ID dynamically via `SelfSigningTeam`; configure `config/release.mk` with your Team ID so `make release-check` validates the environment.

To stream logs during testing:

```sh
log stream --predicate 'subsystem == "com.gajeroll.capsawake"' --level debug
```

To clean up after testing, run:

```sh
./scripts/uninstall.sh
```

## Adding localized strings

Localization strings live in `resources/Localizable.xcstrings`. When adding or editing strings:
- Use semantic `snake_case` keys (for example, `menu_enable_capsawake`, `settings_section_general`).
- Always provide both `en` (English) and `ja` (Japanese) localizations.
- Never rename existing keys.
- Preserve format specifiers (e.g. `%lld`, `%@`) identically across all languages.

## Release process

1. Copy the release configuration template:
   ```sh
   cp config/release.example.mk config/release.mk
   ```
2. Fill in `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, and `DEV_ID_SIGNING_IDENTITY` in `config/release.mk`.
3. Verify your release environment:
   ```sh
   make release-check
   ```
4. Verify `CFBundleShortVersionString` in `resources/Info.plist` matches the target release version (e.g., `1.0.0`).
5. Build, sign, notarize, and staple the release archive:
   ```sh
   make notarize
   ```
   This produces `dist/release/CapsAwake-notarized.zip`. Rename this file to `CapsAwake-<version>.zip` (e.g., `CapsAwake-1.0.0.zip`).
6. Push the tag:
   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```
7. The GitHub Actions workflow (`.github/workflows/release.yml`) creates a draft release on tag push via `gh release create --draft`.
8. Upload the notarized zip and publish the release:
   ```sh
   gh release upload v1.0.0 dist/release/CapsAwake-1.0.0.zip
   gh release edit v1.0.0 --draft=false
   ```
   (Do not run a second `gh release create`, as it will fail because the draft release already exists.)

## Pull requests and commits

- Follow [Conventional Commits](https://www.conventionalcommits.org/) for all commits (`feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `release`).
- Keep one logical change per pull request.
- Ensure `make test` and `make lint` pass before submitting.
- Add unit tests for new state machine behavior in `CapsAwakeCoreTests`.
