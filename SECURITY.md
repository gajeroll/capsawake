# Security Policy

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/gajeroll/capsawake/security/advisories/new).
Please do not open a public issue for a vulnerability.

Expect an acknowledgement within a week. There is no bounty programme.

## What runs, and as whom

CapsAwake consists of two processes:

**CapsAwake.app** runs as the current user. It reads and writes the Caps Lock LED through `IOHIDSystem`, optionally installs a Caps Lock event tap (requiring Accessibility permission), reads lid and display state from IOKit, and communicates with the daemon over XPC. It makes no network requests, collects no telemetry, and requires no user account.

**CapsAwakeDaemon** runs as **root**. It is registered via `SMAppService`, located inside the app bundle at `Contents/MacOS/CapsAwakeDaemon`, and launched on demand by launchd when the app connects. It exits automatically after the last client disconnects. It exists because `pmset -a disablesleep` requires root privileges and is the only public mechanism to prevent sleep with the MacBook lid closed and no external display connected.

### What the daemon will do

The full XPC interface is defined in [`CapsAwakeDaemonProtocol`](Sources/CapsAwakeIPC/CapsAwakeDaemonProtocol.swift):

| Method | Effect |
|---|---|
| `setSleepDisabled(_:)` | `pmset -a disablesleep 0\|1`, and holds an `IOPMAssertion` |
| `currentSleepDisabled()` | Reads the setting back |
| `overrideEnergyMode(battery:adapter:)` | `pmset -b\|-c powermode 0\|1\|2` |
| `restoreEnergyMode()` | Restores previous energy modes from baseline |
| `ping()` | Health check (no-op) |

The daemon accepts no filesystem paths, arbitrary shell commands, or unconstrained strings. Energy Mode parameters are strictly validated against a three-case enum. All system commands are invoked using fixed absolute paths and explicit argument arrays — never passed to a shell.

### What it writes outside power settings

One file: `/Library/Application Support/CapsAwake/baseline.plist`, owned by `root:wheel` with permissions `0644`. It records the system values of `SleepDisabled` and Energy Mode prior to CapsAwake modifications, ensuring states are restored even if the daemon crashes or is terminated. The file is accessed with `O_NOFOLLOW` and verified to be a root-owned regular file before reading. Each entry is removed immediately once restored.

## Who may drive the daemon

`NSXPCListener.setConnectionCodeSigningRequirement` enforces code-signing requirements on all connections:

```
identifier "com.gajeroll.capsawake" and anchor apple generic
    and certificate leaf[subject.OU] = "<TEAM_ID>"
```

macOS verifies this requirement against the connecting peer's audit token before the connection is established. The Team ID is the critical constraint: `anchor apple generic` alone is satisfied by any Apple-issued developer certificate, so requiring a specific Team ID prevents unauthorized applications from connecting.

The app validates the daemon using an equivalent requirement specifying `identifier "CapsAwakeDaemon"`.

The XPC requirement's Team ID is read from the process's own code signature at startup, not from a hardcoded constant. A process that can rewrite the daemon is already root. An ad-hoc signature is fail-closed: without a valid Team ID, the daemon rejects all incoming clients, the app refuses connections to the daemon, and there is no `#if DEBUG` bypass.

## What is left behind

When the app terminates normally or crashes, the daemon detects the disconnection, restores baseline settings, and exits. If the daemon process terminates unexpectedly, subsequent instances read the baseline from disk to restore state.

To remove all artifacts, including launchd registrations and the root-owned baseline file, run [`scripts/uninstall.sh`](scripts/uninstall.sh).

## Supported versions

Version 1.0.0 and later (the latest release).
