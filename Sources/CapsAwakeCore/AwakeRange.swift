import Foundation

/// How far CapsAwake goes to keep the Mac awake: what it carries on through, and
/// where it stands aside.
///
/// Every value here is written from the side of staying awake rather than of giving
/// up, because that is what the app is for. Giving up is what the *ends* of these
/// ranges mean, not what they are named after.

/// What to do when the Mac's own sleep time arrives with nobody at the keyboard.
///
/// The time is macOS's, not ours: whatever System Settings has for the power source
/// in use. CapsAwake normally makes it moot, since disabling sleep stops the timer
/// being consulted at all, so this is how to ask for it back.
public enum AwakePastSleepTime: String, CaseIterable, Sendable {
    /// Stay awake. What CapsAwake has always done, and the default.
    case always
    /// Stay awake while the lid is closed, and let the Mac sleep while it is open.
    ///
    /// A closed lid means no keyboard to be idle at, so the sleep time would
    /// otherwise always arrive; this keeps closed-lid work going while still letting
    /// a Mac you walked away from sleep.
    case whileLidClosed
    /// Let the Mac sleep, the same as it would with CapsAwake off.
    case never
}

/// The battery level to keep the Mac awake down to, while it is on battery.
///
/// `nil` means any level: carry on to whatever the Mac does when the battery runs
/// out. Running on the adapter is not a level at all, so nothing here applies.
public struct AwakeBatteryFloor: Equatable, Sendable {
    /// What CapsAwake did before the level could be chosen, and the default.
    public static let standard = 5

    /// The levels offered, low to high. Sleep prevention is released at or below the
    /// chosen one.
    public static let offered = [5, 10, 20, 30]
}
