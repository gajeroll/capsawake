import Foundation

// The state the reducer owns. Split out of `SleepPreventionReducer.swift` for reading
// only; nothing here changed with the move.

/// Whether the user's session is somewhere CapsAwake can do its work.
///
/// The event tap lives in the user's login session and sees nothing at the lock
/// screen, the login window, or another user's session — and secure input takes the
/// keyboard away from it even there. Each field records one observation; what to do
/// about them is the reducer's decision, read through `accessible`.
public struct SessionAccessibility: Equatable, Sendable {
    public var screenLocked: Bool
    public var sessionActive: Bool
    public var secureInputActive: Bool

    public var accessible: Bool { !screenLocked && sessionActive && !secureInputActive }

    public init(
        screenLocked: Bool = false,
        sessionActive: Bool = true,
        secureInputActive: Bool = false
    ) {
        self.screenLocked = screenLocked
        self.sessionActive = sessionActive
        self.secureInputActive = secureInputActive
    }
}

public struct SleepPreventionState: Equatable, Sendable {
    public var desired: Bool
    public var sleepDisabledApplied: Bool
    public var capsLockLEDOn: Bool?
    /// The other switch on the same key: whether the user asked, with Shift+Caps
    /// Lock, for capitals to type again while CapsAwake owns plain Caps Lock.
    ///
    /// The LED stays out of this. It mirrors sleep prevention and nothing else, so
    /// capitals are produced by adding the modifier to key events instead.
    public var capsLockTypingRequested: Bool
    public var dedicatedFilterReady: Bool
    public var dedicatedModeEnabled: Bool
    /// Where the session stands, as observed. The tap is what keeps a lit lock from
    /// typing capitals, so wherever the session cannot be reached the lock must not
    /// stay lit on the app's behalf.
    public var session: SessionAccessibility
    public var displaySleepOnLidClose: Bool
    public var clamshellClosed: Bool?
    public var externalDisplayConnected: Bool?
    /// Whether closing the lid would currently put the Mac to sleep, per IOKit.
    /// Unreliable on its own (can report Yes even when SleepDisabled is set), so
    /// only used for an advisory warning rather than a hard error.
    public var clamshellCausesSleep: Bool?
    public var displaySleepRequestedForClosedLid: Bool
    public var displaySleepAttempts: Int
    public var displaySleepGaveUp: Bool
    /// The mode to impose while sleep prevention is on, or `nil` to leave the
    /// machine's Energy Mode alone.
    public var energyModePlan: EnergyModePlan?
    /// The last plan handed to the daemon, kept whether or not the write succeeded:
    /// a rejected mode can still have landed on one power source, and restoring is
    /// a no-op when the daemon recorded no baseline.
    public var requestedEnergyModePlan: EnergyModePlan?
    public var energyModeWriteFailed: Bool
    public var energyModeAttempts: Int
    public var privilegedError: Bool
    public var dedicatedModeError: Bool
    public var daemonNeedsApproval: Bool
    public var thermalState: ThermalLevel
    public var batteryPercent: Int?
    public var onBattery: Bool
    /// What to do when the Mac's own sleep time arrives with nobody at the keyboard.
    public var awakePastSleepTime: AwakePastSleepTime
    /// The battery level to keep going down to, or `nil` for any level.
    public var awakeBatteryFloor: Int?

    public init(
        desired: Bool = false,
        sleepDisabledApplied: Bool = false,
        capsLockLEDOn: Bool? = nil,
        capsLockTypingRequested: Bool = false,
        dedicatedFilterReady: Bool = true,
        dedicatedModeEnabled: Bool = false,
        session: SessionAccessibility = SessionAccessibility(),
        displaySleepOnLidClose: Bool = true,
        clamshellClosed: Bool? = nil,
        externalDisplayConnected: Bool? = nil,
        clamshellCausesSleep: Bool? = nil,
        displaySleepRequestedForClosedLid: Bool = false,
        displaySleepAttempts: Int = 0,
        displaySleepGaveUp: Bool = false,
        energyModePlan: EnergyModePlan? = nil,
        requestedEnergyModePlan: EnergyModePlan? = nil,
        energyModeWriteFailed: Bool = false,
        energyModeAttempts: Int = 0,
        privilegedError: Bool = false,
        dedicatedModeError: Bool = false,
        daemonNeedsApproval: Bool = false,
        thermalState: ThermalLevel = .nominal,
        batteryPercent: Int? = nil,
        onBattery: Bool = false,
        awakePastSleepTime: AwakePastSleepTime = .always,
        awakeBatteryFloor: Int? = AwakeBatteryFloor.standard
    ) {
        self.desired = desired
        self.sleepDisabledApplied = sleepDisabledApplied
        self.capsLockLEDOn = capsLockLEDOn
        self.capsLockTypingRequested = capsLockTypingRequested
        self.dedicatedFilterReady = dedicatedFilterReady
        self.dedicatedModeEnabled = dedicatedModeEnabled
        self.session = session
        self.displaySleepOnLidClose = displaySleepOnLidClose
        self.clamshellClosed = clamshellClosed
        self.externalDisplayConnected = externalDisplayConnected
        self.clamshellCausesSleep = clamshellCausesSleep
        self.displaySleepRequestedForClosedLid = displaySleepRequestedForClosedLid
        self.displaySleepAttempts = displaySleepAttempts
        self.displaySleepGaveUp = displaySleepGaveUp
        self.energyModePlan = energyModePlan
        self.requestedEnergyModePlan = requestedEnergyModePlan
        self.energyModeWriteFailed = energyModeWriteFailed
        self.energyModeAttempts = energyModeAttempts
        self.privilegedError = privilegedError
        self.dedicatedModeError = dedicatedModeError
        self.daemonNeedsApproval = daemonNeedsApproval
        self.thermalState = thermalState
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
        self.awakePastSleepTime = awakePastSleepTime
        self.awakeBatteryFloor = awakeBatteryFloor
    }
}

public enum ThermalLevel: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}
