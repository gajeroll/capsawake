import Foundation

// Everything that can happen to CapsAwake, as the reducer is told about it. The rule
// the app is built around is that environment changes arrive here rather than being
// written into state directly.

public enum Intent: Equatable, Sendable {
    case userToggled(Bool)
    case externalCapsLockChanged(Bool)
    /// Records a polled or echo-window LED reading without treating it as user intent.
    case capsLockLEDObserved(Bool?)
    /// Shift+Caps Lock: the user's other switch on the same key.
    case capsLockTypingChanged(Bool)
    case inputSourceChanged
    /// The session became reachable or unreachable: the screen locked or unlocked,
    /// the console changed hands, secure input came or went.
    case sessionAccessibilityChanged(SessionAccessibility)
    case sleepDisabledConfirmed(Bool)
    /// Syncs the applied flag to a value read from the machine (e.g. at launch).
    /// Unlike `.sleepDisabledConfirmed`, this may emit a correcting `.setSleepDisabled`.
    case sleepDisabledObserved(Bool)
    case sleepDisabledFailed
    case dedicatedFilterChanged(ready: Bool, enabled: Bool)
    case daemonApprovalChanged(needsApproval: Bool)
    case clamshellChanged(Bool?)
    case externalDisplayChanged(Bool?)
    case clamshellSleepPolicyChanged(Bool?)
    case displaySleepCompleted
    case displaySleepFailed
    case displayWokeWhileLidClosed
    case energyModeConfirmed(EnergyModePlan?)
    case energyModeFailed(EnergyModePlan?)
    case thermalChanged(ThermalLevel)
    case batteryChanged(percent: Int?, onBattery: Bool)
    /// How long the keyboard has gone untouched, with the Mac's own sleep time to
    /// measure it against. `sleepAfterMinutes` is macOS's setting for the power
    /// source in use: zero when it is set never to sleep, `nil` when unread.
    /// `displayAsleep` is whether the display is off, because macOS never
    /// idle-sleeps while it is on — the sleep time cannot have arrived in front of
    /// a lit screen.
    case idleObserved(seconds: Int, sleepAfterMinutes: Int?, displayAsleep: Bool)
    case preferenceChanged(PreferencesSnapshot)
    case reconcileTick
    case startup
}

public struct PreferencesSnapshot: Equatable, Sendable {
    public var dedicatedModeEnabled: Bool
    public var displaySleepOnLidClose: Bool
    /// `nil` when the user asked CapsAwake not to touch the Energy Mode.
    public var energyModePlan: EnergyModePlan?
    public var awakePastSleepTime: AwakePastSleepTime
    /// `nil` when the user asked to keep going at any battery level.
    public var awakeBatteryFloor: Int?

    public init(
        dedicatedModeEnabled: Bool = false,
        displaySleepOnLidClose: Bool = true,
        energyModePlan: EnergyModePlan? = nil,
        awakePastSleepTime: AwakePastSleepTime = .always,
        awakeBatteryFloor: Int? = AwakeBatteryFloor.standard
    ) {
        self.dedicatedModeEnabled = dedicatedModeEnabled
        self.displaySleepOnLidClose = displaySleepOnLidClose
        self.energyModePlan = energyModePlan
        self.awakePastSleepTime = awakePastSleepTime
        self.awakeBatteryFloor = awakeBatteryFloor
    }
}
