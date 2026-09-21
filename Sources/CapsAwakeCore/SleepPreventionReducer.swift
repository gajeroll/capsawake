import Foundation

public enum SleepPreventionReducer {
    public static let maxDisplaySleepAttempts = 3

    /// Energy Mode is a convenience, not the app's job, so a write that keeps
    /// failing is retried on the reconcile tick a few times and then dropped
    /// rather than forking `pmset` forever.
    public static let maxEnergyModeAttempts = 3

    /// Delays that absorb powerd's grace period, then back off on retries.
    public static let displaySleepDelaysSeconds: [Double] = [1.5, 4, 10]

    public static func reduce(
        state: SleepPreventionState,
        intent: Intent
    ) -> ReduceResult {
        var state = state
        var effects: [Effect] = []

        func syncSystemState() {
            let shouldPrevent = effectiveDesired(state)
            // The lock follows sleep prevention only while the session can be
            // reached; the same comparison on every pass is what keeps it released
            // through the reconcile ticks, and what retries a write that failed.
            let ledTarget = capsLockLEDTarget(state)
            if state.sleepDisabledApplied != shouldPrevent {
                effects.append(.setSleepDisabled(shouldPrevent))
            }
            if let led = state.capsLockLEDOn, led != ledTarget {
                effects.append(.setCapsLockLED(ledTarget))
            } else if state.capsLockLEDOn == nil, ledTarget {
                effects.append(.setCapsLockLED(true))
            }
            appendDisplaySleepIfNeeded(&state, &effects)
            appendEnergyModeIfNeeded(&state, &effects)
            effects.append(.showStatus(statusPresentation(for: state)))
        }

        switch intent {
        case .userToggled(let on):
            state.desired = on
            state.privilegedError = false
            syncSystemState()

        // The Caps Lock LED is the switch the user actually operates, so a change
        // that did not come from us is an instruction, not something to undo.
        // Callers must filter out echoes of our own writes before sending this.
        case .externalCapsLockChanged(let on):
            state.capsLockLEDOn = on
            // Unless it happened somewhere the tap cannot reach — the states the
            // lock is released for. There the key is a plain Caps Lock and a press
            // is someone at a password field, so the lock is left wherever they put
            // it, uncorrected; the write that restores ours follows the session
            // coming back.
            if state.dedicatedModeEnabled && !state.session.accessible {
                break
            }
            state.desired = on
            state.privilegedError = false
            syncSystemState()

        case .capsLockLEDObserved(let on):
            state.capsLockLEDOn = on

        // The other switch on the key. Capitals are added to key events, so they
        // need nothing from the hardware — but the press flipped the lock on its way
        // in, so put it straight back rather than waiting to observe where it
        // landed, which is what made the LED blink.
        case .capsLockTypingChanged(let requested):
            state.capsLockTypingRequested = requested
            effects.append(.setCapsLockLED(capsLockLEDTarget(state)))
            effects.append(.showStatus(statusPresentation(for: state)))

        case .inputSourceChanged:
            guard capsLockLEDTarget(state) else {
                return ReduceResult(state: state, effects: effects)
            }
            effects.append(.setCapsLockLED(true))

        // Sync emits the write in whichever direction the change asks for: the
        // release when the session goes out of reach, the restore when it returns.
        case .sessionAccessibilityChanged(let session):
            state.session = session
            syncSystemState()

        case .sleepDisabledConfirmed(let disabled):
            state.sleepDisabledApplied = disabled
            state.privilegedError = false
            appendDisplaySleepIfNeeded(&state, &effects)
            effects.append(.showStatus(statusPresentation(for: state)))

        // Launch-time (or out-of-band) observation: adopt the machine's value and
        // let sync emit a correcting write when it disagrees with `desired`.
        case .sleepDisabledObserved(let disabled):
            state.sleepDisabledApplied = disabled
            state.privilegedError = false
            syncSystemState()

        case .sleepDisabledFailed:
            state.privilegedError = true
            effects.append(.showStatus(statusPresentation(for: state)))

        case .dedicatedFilterChanged(let ready, let enabled):
            state.dedicatedFilterReady = ready
            state.dedicatedModeEnabled = enabled
            state.dedicatedModeError = enabled && !ready
            if enabled && !ready {
                state.desired = false
                syncSystemState()
            } else {
                effects.append(.showStatus(statusPresentation(for: state)))
            }

        // Only reported, never used to override `desired`: the user's switch should
        // still read as on while they go and approve the daemon.
        case .daemonApprovalChanged(let needsApproval):
            state.daemonNeedsApproval = needsApproval
            effects.append(.showStatus(statusPresentation(for: state)))

        case .clamshellChanged(let closed):
            state.clamshellClosed = closed
            if closed != true {
                resetDisplaySleepTracking(&state)
            }
            appendDisplaySleepIfNeeded(&state, &effects)

        case .externalDisplayChanged(let connected):
            state.externalDisplayConnected = connected
            if connected == true {
                resetDisplaySleepTracking(&state)
            }
            appendDisplaySleepIfNeeded(&state, &effects)

        case .clamshellSleepPolicyChanged(let causesSleep):
            state.clamshellCausesSleep = causesSleep

        case .displaySleepCompleted:
            state.displaySleepRequestedForClosedLid = true

        case .displaySleepFailed:
            state.displaySleepRequestedForClosedLid = false
            recordDisplaySleepAttempt(&state, &effects)

        case .displayWokeWhileLidClosed:
            state.displaySleepRequestedForClosedLid = false
            recordDisplaySleepAttempt(&state, &effects)
            if !state.displaySleepGaveUp {
                appendDisplaySleepIfNeeded(&state, &effects)
            }

        // Replies are matched against the outstanding request so a late one from a
        // superseded plan cannot clear or set the retry flag.
        case .energyModeConfirmed(let plan):
            guard plan == state.requestedEnergyModePlan else { break }
            state.energyModeWriteFailed = false

        case .energyModeFailed(let plan):
            guard plan == state.requestedEnergyModePlan else { break }
            state.energyModeWriteFailed = true

        case .thermalChanged(let level):
            state.thermalState = level
            // A closed lid inside a bag cannot shed heat; release earlier than when
            // the machine is open and ventilated.
            let shouldRelease =
                level == .critical
                || (level == .serious && state.clamshellClosed == true)
            if shouldRelease, state.desired {
                state.desired = false
                syncSystemState()
                effects.append(.notifyUser(.thermalShutdown))
            }

        case .batteryChanged(let percent, let onBattery):
            state.batteryPercent = percent
            state.onBattery = onBattery
            if onBattery,
                let percent,
                let floor = state.awakeBatteryFloor,
                percent <= floor,
                state.desired
            {
                state.desired = false
                syncSystemState()
                effects.append(.notifyUser(.batteryShutdown))
            }

        // Standing aside at the sleep time means standing aside at the moment the
        // Mac would have slept by itself — and that moment can only follow the
        // display going dark, because powerd never idle-sleeps the system while a
        // display is on. Without the display check the release could come in front
        // of a lit screen (sleep timer shorter than the display timer), or on a Mac
        // whose display is set never to sleep and which would therefore never have
        // slept at all.
        case .idleObserved(let seconds, let sleepAfterMinutes, let displayAsleep):
            if state.desired,
                shouldSleepAtSleepTime(state),
                displayAsleep,
                let minutes = sleepAfterMinutes,
                minutes > 0,
                seconds >= minutes * 60
            {
                state.desired = false
                syncSystemState()
                effects.append(.notifyUser(.sleepTimeReached))
            }

        case .preferenceChanged(let prefs):
            state.dedicatedModeEnabled = prefs.dedicatedModeEnabled
            state.displaySleepOnLidClose = prefs.displaySleepOnLidClose
            state.energyModePlan = prefs.energyModePlan
            state.awakePastSleepTime = prefs.awakePastSleepTime
            state.awakeBatteryFloor = prefs.awakeBatteryFloor
            // Kept in step with the pair it summarises. Leaving it stale here once
            // let the app fail closed while the icon still read as idle.
            state.dedicatedModeError = prefs.dedicatedModeEnabled && !state.dedicatedFilterReady
            if prefs.dedicatedModeEnabled && !state.dedicatedFilterReady {
                state.desired = false
                syncSystemState()
            } else {
                appendDisplaySleepIfNeeded(&state, &effects)
                appendEnergyModeIfNeeded(&state, &effects)
                // Handing the key over, or taking it back, changes where capitals
                // come from, and the icon shows capitals.
                effects.append(.showStatus(statusPresentation(for: state)))
            }

        case .reconcileTick, .startup:
            syncSystemState()
        }

        return ReduceResult(state: state, effects: effects)
    }

    private static func resetDisplaySleepTracking(_ state: inout SleepPreventionState) {
        state.displaySleepRequestedForClosedLid = false
        state.displaySleepAttempts = 0
        state.displaySleepGaveUp = false
    }

    private static func recordDisplaySleepAttempt(
        _ state: inout SleepPreventionState,
        _ effects: inout [Effect]
    ) {
        guard !state.displaySleepGaveUp else { return }
        state.displaySleepAttempts += 1
        if state.displaySleepAttempts >= maxDisplaySleepAttempts {
            state.displaySleepGaveUp = true
            effects.append(.notifyUser(.displaySleepBlocked))
        }
    }

    /// Emits the Energy Mode write, if any, that matches the current switch state.
    ///
    /// Turning sleep prevention off restores the previous modes even when the last
    /// override failed, because it may have landed on one power source.
    private static func appendEnergyModeIfNeeded(
        _ state: inout SleepPreventionState,
        _ effects: inout [Effect]
    ) {
        let target = effectiveDesired(state) ? state.energyModePlan : nil
        if state.requestedEnergyModePlan != target {
            state.requestedEnergyModePlan = target
            state.energyModeWriteFailed = false
            state.energyModeAttempts = 1
            effects.append(.setEnergyMode(target))
            return
        }
        // Retry a failed write on later ticks: the daemon may have been coming up,
        // or waiting for approval.
        guard state.energyModeWriteFailed,
            state.energyModeAttempts < maxEnergyModeAttempts
        else { return }
        state.energyModeAttempts += 1
        effects.append(.setEnergyMode(target))
    }

    private static func appendDisplaySleepIfNeeded(
        _ state: inout SleepPreventionState,
        _ effects: inout [Effect]
    ) {
        guard effectiveDesired(state) else { return }
        guard state.displaySleepOnLidClose else { return }
        guard state.clamshellClosed == true else { return }
        guard state.externalDisplayConnected == false else { return }
        guard !state.displaySleepRequestedForClosedLid else { return }
        guard !state.displaySleepGaveUp else { return }
        let index = min(state.displaySleepAttempts, displaySleepDelaysSeconds.count - 1)
        let delay = displaySleepDelaysSeconds[index]
        effects.append(.requestDisplaySleep(afterSeconds: delay))
    }
}
