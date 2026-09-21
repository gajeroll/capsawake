# Architecture

CapsAwake consists of a menu bar application and a privileged root daemon. Because the Caps Lock key functions simultaneously as a keep-awake switch and a standard system modifier whose state can change externally, all policy decisions are centralized in a deterministic, testable state machine.

## Modules

| Target | Contains | Allowed imports |
|---|---|---|
| `CapsAwakeCore` | State machine, preferences, shared value types | Foundation only |
| `CapsAwakeIPC` | Shared XPC protocol and interfaces | `CapsAwakeCore` |
| `CapsAwakeSystem` | macOS integration: IOKit, `pmset`, `hidutil`, event tap | `CapsAwakeCore`, `CapsAwakeIPC` |
| `CapsAwakeUI` | SwiftUI views and observable view models | `CapsAwakeCore` |
| `CapsAwakeDaemon` | Privileged root daemon | `CapsAwakeCore`, `CapsAwakeIPC`, `CapsAwakeSystem` |
| `CapsAwake` | App entry point, lifecycle management, system monitors | All targets |

Core architectural rules:

1. **`CapsAwakeCore` imports Foundation only.** No AppKit, IOKit, or SwiftUI dependencies. Core state logic can be tested without hardware dependencies.
2. **`CapsAwakeUI` does not invoke system APIs directly.** Views observe state models published from the core store.
3. **`CapsAwakeSystem` avoids AppKit.** The privileged daemon links against `CapsAwakeSystem`. Consequently, `NSEvent` mappings reside in `CapsAwake` while `CGEventFlags` handling resides in `CapsAwakeSystem`.

## How a decision is made

All state transitions follow a unidirectional data flow:

```
External Event      ──▶  Intent  ──▶  SleepPreventionReducer  ──▶  [Effect]
(key press, lid,                           │                          │
 response, timer)                          ▼                          ▼
                                 SleepPreventionState        AppController.apply
                                          │                          │
                                          ▼                          ▼
                                   AppModel.render            Daemon, LED,
                                   (Menu, Settings)           display sleep, alerts
```

- **`Intent`**: The exclusive vehicle for state changes. Hardware observations (lid close, LED toggle, battery change, XPC responses) are dispatched as intents to `SleepPreventionStore`. Direct state mutation is prohibited.
- **`SleepPreventionReducer.reduce`**: Pure reducer function of `(state, intent) -> (state, [Effect])`. Centralizes all policy logic: thermal limits, battery floors, display sleep timeouts, and backoff retries.
- **`Effect`**: Declarative descriptions of external actions executed by `AppController.apply(_:)`.
- **Projections**: Derived properties (`effectiveDesired`, `capitalsInEffect`, `statusPresentation`, `systemAccess`) consumed by UI layers to ensure consistent presentation across menu and settings surfaces.

This design enables complex environmental scenarios (such as low battery combined with thermal pressure while the lid is closed) to be verified through unit tests without physical hardware.

## System monitors

`AppController` coordinates subsystem lifecycles and dispatches observed events as intents:

| Type | Function |
|---|---|
| `CapsLockSwitch` | Monitors Caps Lock state via event tap, `NSEvent` monitors, or periodic LED polling |
| `DedicatedModeSupervisor` | Manages the event tap and tracks Accessibility permission status |
| `PowerEnvironmentMonitor` | Tracks power source changes, battery levels, thermal state, and system wake events |
| `DaemonRegistrar` | Manages `SMAppService` daemon registration |
| `SleepTimerCache` | Caches system sleep timer settings |
| `PreferenceWatcher` | Observes `UserDefaults` updates |
| `CapsLockDelayGuardian` | Manages keyboard `CapsLockDelay` overrides |
| `SettingsWindowPresenter` | Controls Settings window lifecycle and activation |
| `UserNotifier` | Dispatches system notifications |

### Caps Lock event discrimination

Caps Lock state changes arrive through three paths: the event tap, `NSEvent` monitors, or periodic IOKit LED polling. CapsAwake also writes LED states back to hardware, as does macOS during input source transitions.

To distinguish genuine user input from feedback echoes of software writes, CapsAwake uses brief suppression windows and checks reported lock values against stored state. A user press toggles lock state to an unexpected value; a release or software echo reports the expected state.

## Process model and IPC

The application communicates with `CapsAwakeDaemon` via XPC over `NSXPCListener`. Both processes enforce mutual code-signing requirements checking bundle identifiers and Apple Team IDs. Refer to [SECURITY.md](../SECURITY.md) for full trust boundary specifications.

The daemon is launched on demand by launchd, exits when its last client disconnects, and restores previous system power settings on exit. To survive unexpected termination or replacement mid-override, previous power baselines are written to disk before applying changes.

## Code navigation

- [`SleepPreventionReducer.swift`](../Sources/CapsAwakeCore/SleepPreventionReducer.swift): Core business logic and state machine reducer.
- [`AppController.swift`](../Sources/CapsAwake/AppController.swift): Application lifecycle and effect dispatcher.
- [`CapsLockSwitch.swift`](../Sources/CapsAwake/CapsLockSwitch.swift): Caps Lock hardware and event handling.
