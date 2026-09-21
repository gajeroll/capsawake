import CapsAwakeCore

extension AppModel {
    /// Brings everything the menu and Settings render into line with one state.
    ///
    /// All four values are derived from the same `SleepPreventionState` through the
    /// reducer's own projections, so the icon, the switches and the warning rows cannot
    /// disagree about the same keyboard — which they did, back when each was published
    /// from a different place.
    ///
    /// Each is assigned only when it actually changes. Observation notifies on every
    /// assignment rather than on a change, so without this the reconcile tick would
    /// re-render the menu bar label every five seconds while nothing was happening.
    public func render(_ state: SleepPreventionState) {
        let presentation = SleepPreventionReducer.statusPresentation(for: state)
        if self.presentation != presentation { self.presentation = presentation }

        // Published alongside the icon rather than derived from it, so the menu can
        // name every outstanding permission instead of only the highest-ranked one.
        let access = SleepPreventionReducer.systemAccess(for: state)
        if systemAccess != access { systemAccess = access }

        let warning = SleepPreventionReducer.shouldWarnLidCloseMaySleep(state)
        if lidCloseWarning != warning { lidCloseWarning = warning }

        // The same value the icon's capitals axis is drawn from, so the switch cannot
        // drift from the icon.
        let capitals = SleepPreventionReducer.capitalsInEffect(state)
        if capitalsLocked != capitals { capitalsLocked = capitals }
    }
}
