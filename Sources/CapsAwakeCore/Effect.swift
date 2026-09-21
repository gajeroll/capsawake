import Foundation

// What the reducer asks the app to do, and what it asks the UI to show. Effects are
// values, so a decision can be asserted in a test without a Mac to carry it out on.

public enum Effect: Equatable, Sendable {
    case setSleepDisabled(Bool)
    case setCapsLockLED(Bool)
    /// Ask the display to sleep after a relative delay.
    ///
    /// The delay absorbs powerd's own `delayDisplayOff` grace period on the first
    /// attempt, and backs off on later retries when another process is holding a
    /// display-sleep assertion.
    case requestDisplaySleep(afterSeconds: Double)
    /// Impose a mode on each power source, or restore the modes from before
    /// CapsAwake changed them (`nil`).
    case setEnergyMode(EnergyModePlan?)
    case showStatus(StatusPresentation)
    case notifyUser(NotificationKind)
}

/// The two switches on the key are shown on two axes of the icon, so either one can
/// be read off it on its own.
public enum StatusPresentation: Equatable, Sendable {
    case idle
    case active(capitals: Bool)
    /// Capitals without sleep prevention.
    case capsLockTyping
    case error(ErrorReason)
}

public enum ErrorReason: Equatable, Sendable {
    case privileged
    case dedicatedPermission
    case daemonApproval
}

public enum NotificationKind: Equatable, Sendable {
    case thermalShutdown
    case batteryShutdown
    case sleepTimeReached
    case displaySleepBlocked
}

public struct ReduceResult: Equatable, Sendable {
    public var state: SleepPreventionState
    public var effects: [Effect]

    public init(state: SleepPreventionState, effects: [Effect]) {
        self.state = state
        self.effects = effects
    }
}
