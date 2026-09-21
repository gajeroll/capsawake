import Foundation

/// What the rest of the app reads off the state, as opposed to what changes it.
///
/// The menu, the status icon and the Settings window all render from these rather than
/// from the state's stored properties, so the two switches on the key cannot be
/// described differently in two places. Moved out of `SleepPreventionReducer.swift`
/// unchanged.
extension SleepPreventionReducer {

    public static func effectiveDesired(_ state: SleepPreventionState) -> Bool {
        guard state.desired else { return false }
        if state.dedicatedModeEnabled && !state.dedicatedFilterReady {
            return false
        }
        return true
    }

    /// Where the hardware lock should stand as things are.
    ///
    /// The LED mirrors sleep prevention, but only while the event filter can strip
    /// the capitals a lit lock implies. Wherever it cannot — the lock screen, the
    /// login window, another user's session, secure input — a lit lock types
    /// capitals nobody can switch off, so ours goes out until the session comes
    /// back. Without Dedicated Mode there is no filter and the lit lock is honest
    /// caps typing, exactly what a hardware Caps Lock does in those places, so it
    /// is left to mean what it says.
    public static func capsLockLEDTarget(_ state: SleepPreventionState) -> Bool {
        effectiveDesired(state) && (!state.dedicatedModeEnabled || state.session.accessible)
    }

    /// Whether Caps Lock is locking to capitals as things stand, which is the axis
    /// of the status icon that the fill is drawn on and the state the switch in the
    /// menu and in Settings reports.
    ///
    /// Where capitals come from depends on who owns the key. While it is CapsAwake's,
    /// they are added to key events and only the capitals combination asks for them.
    /// While it is not, they come from the hardware lock — which is also the switch,
    /// so capitals are on exactly while sleep prevention is.
    public static func capitalsInEffect(_ state: SleepPreventionState) -> Bool {
        state.dedicatedModeEnabled ? state.capsLockTypingRequested : effectiveDesired(state)
    }

    /// Whether the Mac's own sleep time is being honoured as things stand.
    ///
    /// A closed lid is no keyboard to be idle at, so on `.whileLidClosed` the timer
    /// only counts while the lid is open — which is the difference between walking
    /// away from a Mac and working on one you have closed. An unknown lid is read as
    /// open: leaving a Mac awake for want of a lid reading is the failure that keeps
    /// a laptop cooking in a bag.
    static func shouldSleepAtSleepTime(_ state: SleepPreventionState) -> Bool {
        switch state.awakePastSleepTime {
        case .always: false
        case .whileLidClosed: state.clamshellClosed != true
        case .never: true
        }
    }

    /// Every permission CapsAwake depends on, whether or not anything is wrong with
    /// it, in the order they matter.
    ///
    /// The daemon comes first because nothing can change the sleep setting without
    /// it, while a missing Accessibility grant only blocks all-caps.
    public static func systemAccess(for state: SleepPreventionState) -> [SystemAccessItem] {
        [
            SystemAccessItem(kind: .backgroundDaemon, status: daemonAccess(state)),
            SystemAccessItem(kind: .accessibility, status: accessibilityAccess(state)),
        ]
    }

    private static func daemonAccess(_ state: SleepPreventionState) -> SystemAccessStatus {
        if state.daemonNeedsApproval { return .awaitingApproval }
        // Approved and still unable to write: the daemon may be missing, blocked, or
        // gone. Either way the sleep setting is not ours to change.
        if state.privilegedError { return .failing }
        return .granted
    }

    /// Read from the live pair rather than `dedicatedModeError` so that a preference
    /// change which fails closed is explained the moment it takes effect.
    private static func accessibilityAccess(_ state: SleepPreventionState) -> SystemAccessStatus {
        guard state.dedicatedModeEnabled else { return .notNeeded }
        return state.dedicatedFilterReady ? .granted : .awaitingApproval
    }

    public static func statusPresentation(for state: SleepPreventionState) -> StatusPresentation {
        // Derived from the list the menu and Settings render, so a warning icon
        // always has a row behind it that says what to do about it.
        if let reason = systemAccess(for: state).lazy.compactMap(\.errorReason).first {
            return .error(reason)
        }
        if effectiveDesired(state) {
            return .active(capitals: capitalsInEffect(state))
        }
        return capitalsInEffect(state) ? .capsLockTyping : .idle
    }

    /// Advisory only: warn when the user has sleep prevention on, the lid would
    /// still cause sleep, and there is no external display to fall back on.
    public static func shouldWarnLidCloseMaySleep(_ state: SleepPreventionState) -> Bool {
        guard effectiveDesired(state) else { return false }
        guard state.clamshellCausesSleep == true else { return false }
        guard state.externalDisplayConnected != true else { return false }
        return true
    }
}
