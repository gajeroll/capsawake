import Testing

@testable import CapsAwakeCore

@Test func userToggleOnRequestsSleepDisabledAndLED() {
    var state = SleepPreventionState()
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true))
    state = result.state
    #expect(state.desired == true)
    #expect(result.effects.contains(.setSleepDisabled(true)))
    #expect(result.effects.contains(.setCapsLockLED(true)))
}

@Test func inputSourceChangedDoesNotChangeDesiredWhenUserTurnedOff() {
    let state = SleepPreventionState(desired: false)
    let result = SleepPreventionReducer.reduce(state: state, intent: .inputSourceChanged)
    #expect(result.state.desired == false)
    #expect(result.effects.isEmpty)
}

@Test func inputSourceChangedReassertsLEDWhenDesiredOn() {
    let state = SleepPreventionState(desired: true, capsLockLEDOn: false)
    let result = SleepPreventionReducer.reduce(state: state, intent: .inputSourceChanged)
    #expect(result.state.desired == true)
    #expect(result.effects == [.setCapsLockLED(true)])
}

@Test func externalCapsLockOnTurnsSleepPreventionOn() {
    let state = SleepPreventionState(desired: false, capsLockLEDOn: false)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .externalCapsLockChanged(true)
    )
    #expect(result.state.desired == true)
    #expect(result.effects.contains(.setSleepDisabled(true)))
    // The LED is already where we want it, so do not drive it again.
    #expect(!result.effects.contains(.setCapsLockLED(true)))
    #expect(result.effects.contains(.showStatus(.active(capitals: true))))
}

@Test func externalCapsLockOffTurnsSleepPreventionOff() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .externalCapsLockChanged(false)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(Effect.setSleepDisabled(false)))
    #expect(result.effects.contains(.showStatus(.idle)))
}

@Test func externalCapsLockOnStillFailsClosedWithoutFilter() {
    let state = SleepPreventionState(
        capsLockLEDOn: false,
        dedicatedFilterReady: false,
        dedicatedModeEnabled: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .externalCapsLockChanged(true)
    )
    #expect(result.state.desired == true)
    #expect(!result.effects.contains(.setSleepDisabled(true)))
    #expect(result.effects.contains(.setCapsLockLED(false)))
}

@Test func daemonApprovalOutranksAccessibilityInTheStatusIcon() {
    let state = SleepPreventionState(dedicatedModeError: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .daemonApprovalChanged(needsApproval: true)
    )
    #expect(result.effects == [.showStatus(.error(.daemonApproval))])
}

@Test func daemonApprovalDoesNotOverrideTheUsersSwitch() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true, capsLockLEDOn: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .daemonApprovalChanged(needsApproval: true)
    )
    #expect(result.state.desired == true)
    #expect(!result.effects.contains(.setCapsLockLED(false)))
}

@Test func daemonApprovalClearedRestoresTheUnderlyingStatus() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        daemonNeedsApproval: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .daemonApprovalChanged(needsApproval: false)
    )
    #expect(result.effects == [.showStatus(.active(capitals: true))])
}

@Test func dedicatedModeWithoutFilterFailsClosed() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        dedicatedFilterReady: false,
        dedicatedModeEnabled: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .dedicatedFilterChanged(ready: false, enabled: true)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(Effect.setSleepDisabled(false)))
}

@Test func displayWokeWhileLidClosedRequestsDisplaySleepAgain() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        displaySleepOnLidClose: true,
        clamshellClosed: true,
        externalDisplayConnected: false,
        displaySleepRequestedForClosedLid: true
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .displayWokeWhileLidClosed)
    #expect(result.state.displaySleepRequestedForClosedLid == false)
    #expect(result.state.displaySleepAttempts == 1)
    #expect(
        result.effects.contains(
            .requestDisplaySleep(afterSeconds: SleepPreventionReducer.displaySleepDelaysSeconds[1])
        )
    )
}

@Test func closingThenOpeningThenClosingRequestsDisplaySleepTwice() {
    var state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        displaySleepOnLidClose: true,
        externalDisplayConnected: false
    )
    var result = SleepPreventionReducer.reduce(state: state, intent: .clamshellChanged(true))
    state = result.state
    #expect(result.effects.contains(.requestDisplaySleep(afterSeconds: 1.5)))

    result = SleepPreventionReducer.reduce(state: state, intent: .displaySleepCompleted)
    state = result.state
    #expect(state.displaySleepRequestedForClosedLid == true)

    result = SleepPreventionReducer.reduce(state: state, intent: .clamshellChanged(false))
    state = result.state
    #expect(state.displaySleepRequestedForClosedLid == false)
    #expect(state.displaySleepAttempts == 0)
    #expect(
        !result.effects.contains {
            if case .requestDisplaySleep = $0 { true } else { false }
        }
    )

    result = SleepPreventionReducer.reduce(state: state, intent: .clamshellChanged(true))
    #expect(result.effects.contains(.requestDisplaySleep(afterSeconds: 1.5)))
}

@Test func openingLidDoesNotRequestDisplaySleep() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        displaySleepOnLidClose: true,
        clamshellClosed: true,
        externalDisplayConnected: false,
        displaySleepRequestedForClosedLid: true
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .clamshellChanged(false))
    #expect(result.state.clamshellClosed == false)
    #expect(result.state.displaySleepRequestedForClosedLid == false)
    #expect(
        !result.effects.contains {
            if case .requestDisplaySleep = $0 { true } else { false }
        }
    )
}

@Test func displaySleepGivesUpAfterThreeFailures() {
    var state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        displaySleepOnLidClose: true,
        clamshellClosed: true,
        externalDisplayConnected: false
    )
    for _ in 0..<2 {
        let result = SleepPreventionReducer.reduce(state: state, intent: .displaySleepFailed)
        state = result.state
        #expect(!result.effects.contains(.notifyUser(.displaySleepBlocked)))
    }
    let final = SleepPreventionReducer.reduce(state: state, intent: .displaySleepFailed)
    #expect(final.state.displaySleepGaveUp == true)
    #expect(final.state.displaySleepAttempts == 3)
    #expect(final.effects.contains(.notifyUser(.displaySleepBlocked)))
}

@Test func openingLidResetsDisplaySleepGiveUp() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        displaySleepOnLidClose: true,
        clamshellClosed: true,
        externalDisplayConnected: false,
        displaySleepAttempts: 3,
        displaySleepGaveUp: true
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .clamshellChanged(false))
    #expect(result.state.displaySleepAttempts == 0)
    #expect(result.state.displaySleepGaveUp == false)
}

@Test func thermalSeriousReleasesWhenLidClosed() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        clamshellClosed: true
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .thermalChanged(.serious))
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.notifyUser(.thermalShutdown)))
}

@Test func thermalSeriousDoesNotReleaseWhenLidOpen() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        clamshellClosed: false
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .thermalChanged(.serious))
    #expect(result.state.desired == true)
    #expect(!result.effects.contains(.notifyUser(.thermalShutdown)))
}

@Test func capsLockLEDObservedDoesNotChangeDesired() {
    let state = SleepPreventionState(desired: false, capsLockLEDOn: false)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .capsLockLEDObserved(true)
    )
    #expect(result.state.desired == false)
    #expect(result.state.capsLockLEDOn == true)
    #expect(result.effects.isEmpty)
}

@Test func sleepDisabledObservedPullsBackWhenDesiredOff() {
    let state = SleepPreventionState(desired: false, sleepDisabledApplied: false)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .sleepDisabledObserved(true)
    )
    #expect(result.state.sleepDisabledApplied == true)
    #expect(result.effects.contains(.setSleepDisabled(false)))
}

/// The daemon exiting with its last client, or being replaced by an update, puts the
/// setting back underneath us. Reading the machine is what notices; this is what has
/// to happen next, or the Mac sleeps at the next idle timeout with the switch still on.
@Test func sleepPreventionLostUnderneathUsIsWrittenAgain() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .sleepDisabledObserved(false)
    )
    #expect(result.effects.contains(.setSleepDisabled(true)))
}

@Test func lidCloseWarningRequiresCausesSleepWithoutExternalDisplay() {
    let warn = SleepPreventionState(
        desired: true,
        externalDisplayConnected: false,
        clamshellCausesSleep: true
    )
    #expect(SleepPreventionReducer.shouldWarnLidCloseMaySleep(warn))

    let withDisplay = SleepPreventionState(
        desired: true,
        externalDisplayConnected: true,
        clamshellCausesSleep: true
    )
    #expect(!SleepPreventionReducer.shouldWarnLidCloseMaySleep(withDisplay))

    let idle = SleepPreventionState(
        desired: false,
        externalDisplayConnected: false,
        clamshellCausesSleep: true
    )
    #expect(!SleepPreventionReducer.shouldWarnLidCloseMaySleep(idle))
}

@Test func turningOnImposesTheEnergyModePlan() {
    let state = SleepPreventionState(energyModePlan: EnergyModePlan(.low))
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true))
    #expect(result.effects.contains(.setEnergyMode(EnergyModePlan(.low))))
    #expect(result.state.requestedEnergyModePlan == EnergyModePlan(.low))
}

@Test func turningOffRestoresTheEnergyMode() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        energyModePlan: EnergyModePlan(.low),
        requestedEnergyModePlan: EnergyModePlan(.low)
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(false))
    #expect(result.effects.contains(.setEnergyMode(nil)))
    #expect(result.state.requestedEnergyModePlan == nil)
}

@Test func noPlanLeavesTheEnergyModeAlone() {
    let state = SleepPreventionState()
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true))
    #expect(!result.effects.contains { if case .setEnergyMode = $0 { true } else { false } })
}

@Test func changingTheModeWhileOnReappliesIt() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        energyModePlan: EnergyModePlan(.low),
        requestedEnergyModePlan: EnergyModePlan(.low)
    )
    let split = EnergyModePlan(battery: .low, adapter: .high)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .preferenceChanged(PreferencesSnapshot(energyModePlan: split))
    )
    #expect(result.effects.contains(.setEnergyMode(split)))
}

@Test func failedEnergyModeWriteRetriesOnTicksThenStops() {
    var state = SleepPreventionState(energyModePlan: EnergyModePlan(.low))
    state = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true)).state
    #expect(state.energyModeAttempts == 1)

    for attempt in 1..<SleepPreventionReducer.maxEnergyModeAttempts {
        state =
            SleepPreventionReducer.reduce(
                state: state,
                intent: .energyModeFailed(EnergyModePlan(.low))
            ).state
        let result = SleepPreventionReducer.reduce(state: state, intent: .reconcileTick)
        state = result.state
        #expect(result.effects.contains(.setEnergyMode(EnergyModePlan(.low))))
        #expect(state.energyModeAttempts == attempt + 1)
    }

    state =
        SleepPreventionReducer.reduce(
            state: state,
            intent: .energyModeFailed(EnergyModePlan(.low))
        ).state
    let exhausted = SleepPreventionReducer.reduce(state: state, intent: .reconcileTick)
    #expect(!exhausted.effects.contains { if case .setEnergyMode = $0 { true } else { false } })
}

// The daemon may have set one power source before refusing the other, so the
// restore has to happen even though the override reported failure.
@Test func failedOverrideStillRestoresWhenTurnedOff() {
    var state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        energyModePlan: EnergyModePlan(.high),
        requestedEnergyModePlan: EnergyModePlan(.high)
    )
    state =
        SleepPreventionReducer.reduce(
            state: state,
            intent: .energyModeFailed(EnergyModePlan(.high))
        ).state
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(false))
    #expect(result.effects.contains(.setEnergyMode(nil)))
}

@Test func staleEnergyModeReplyDoesNotClearTheRetryFlag() {
    let state = SleepPreventionState(
        desired: true,
        energyModePlan: EnergyModePlan(.low),
        requestedEnergyModePlan: EnergyModePlan(.low),
        energyModeWriteFailed: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .energyModeConfirmed(EnergyModePlan(.high))
    )
    #expect(result.state.energyModeWriteFailed == true)
}

@Test func thermalCriticalTurnsOffDesired() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(state: state, intent: .thermalChanged(.critical))
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.notifyUser(.thermalShutdown)))
}

@Test func lowBatteryTurnsOffDesired() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .batteryChanged(percent: 4, onBattery: true)
    )
    #expect(result.state.desired == false)
}

@Test func aHigherBatteryFloorIsLetGoOfSooner() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakeBatteryFloor: 20
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .batteryChanged(percent: 18, onBattery: true)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.notifyUser(.batteryShutdown)))
}

@Test func keepingAwakeAtAnyLevelRunsTheBatteryDown() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakeBatteryFloor: nil
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .batteryChanged(percent: 1, onBattery: true)
    )
    #expect(result.state.desired == true)
}

/// The default, and what CapsAwake did before the sleep time could be honoured.
@Test func stayingAwakeIgnoresTheSleepTime() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 3600, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == true)
}

@Test func reachingTheSleepTimeTurnsOffDesired() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakePastSleepTime: .never
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 600, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.setSleepDisabled(false)))
    #expect(result.effects.contains(.notifyUser(.sleepTimeReached)))
}

/// macOS never idle-sleeps while a display is on — powerd holds an assertion saying
/// so — which makes the display going dark part of "the moment the Mac would have
/// slept". A sleep timer shorter than the display timer, or a display set never to
/// sleep, would otherwise release the switch in front of a lit screen the Mac was
/// never going to sleep behind.
@Test func aLitDisplayMeansTheSleepTimeHasNotArrived() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakePastSleepTime: .never
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 3600, sleepAfterMinutes: 10, displayAsleep: false)
    )
    #expect(result.state.desired == true)
    #expect(!result.effects.contains(.notifyUser(.sleepTimeReached)))
}

@Test func idleShorterThanTheSleepTimeChangesNothing() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakePastSleepTime: .never
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 599, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == true)
}

/// A Mac set never to sleep has no sleep time to arrive at, however long it is left.
@Test func aMacThatNeverSleepsHasNoSleepTimeToReach() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        awakePastSleepTime: .never
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 86400, sleepAfterMinutes: 0, displayAsleep: true)
    )
    #expect(result.state.desired == true)
}

/// A closed lid is no keyboard to be idle at, so this is the choice that keeps
/// closed-lid work going while still letting a Mac you walked away from sleep.
@Test func aClosedLidCarriesOnPastTheSleepTime() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        clamshellClosed: true,
        awakePastSleepTime: .whileLidClosed
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 3600, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == true)
}

@Test func anOpenLidSleepsAtTheSleepTime() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        clamshellClosed: false,
        awakePastSleepTime: .whileLidClosed
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 3600, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.notifyUser(.sleepTimeReached)))
}

/// Nothing to let go of, so nothing to say about it: the reading arrives while the
/// switch is already off after a Caps Lock press or a low battery.
@Test func theSleepTimeDoesNotTurnAnythingOffTwice() {
    let state = SleepPreventionState(desired: false, awakePastSleepTime: .never)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 3600, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.effects.isEmpty)
}

/// The combination only ever reaches the app through the event tap, which runs while
/// Caps Lock is CapsAwake's, so that is the state these press its switch in.
@Test func shiftCapsLockLeavesSleepPreventionAlone() {
    let state = SleepPreventionState(capsLockLEDOn: false, dedicatedModeEnabled: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .capsLockTypingChanged(true)
    )
    #expect(result.state.desired == false)
    #expect(!result.effects.contains(.setSleepDisabled(true)))
    #expect(result.effects.contains(.showStatus(.capsLockTyping)))
}

/// The press flips the hardware lock before the app hears about it, so the LED is
/// written back without waiting to observe where it landed — whatever the app last
/// saw is out of date by then.
@Test func theLockFlippedByShiftCapsLockIsPutBack() {
    for seen in [true, false, nil] as [Bool?] {
        let off = SleepPreventionState(capsLockLEDOn: seen, dedicatedModeEnabled: true)
        #expect(
            SleepPreventionReducer.reduce(state: off, intent: .capsLockTypingChanged(true))
                .effects.contains(.setCapsLockLED(false))
        )
        let on = SleepPreventionState(
            desired: true,
            capsLockLEDOn: seen,
            dedicatedModeEnabled: true
        )
        #expect(
            SleepPreventionReducer.reduce(state: on, intent: .capsLockTypingChanged(false))
                .effects.contains(.setCapsLockLED(true))
        )
    }
}

@Test func capitalsDoNotKeepTheLEDOnWhenSleepPreventionGoesOff() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: true,
        capsLockTypingRequested: true,
        dedicatedModeEnabled: true
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .userToggled(false))
    #expect(result.effects.contains(.setSleepDisabled(false)))
    #expect(result.effects.contains(.setCapsLockLED(false)))
    #expect(result.effects.contains(.showStatus(.capsLockTyping)))
}

/// Both switches are on the icon at once, on axes of their own — while Caps Lock is
/// CapsAwake's and the combination is what capitals come from.
@Test func theStatusIconCarriesBothSwitches() {
    func presentation(desired: Bool, capitals: Bool) -> StatusPresentation {
        SleepPreventionReducer.statusPresentation(
            for: SleepPreventionState(
                desired: desired,
                capsLockTypingRequested: capitals,
                dedicatedModeEnabled: true
            )
        )
    }
    #expect(presentation(desired: false, capitals: false) == .idle)
    #expect(presentation(desired: false, capitals: true) == .capsLockTyping)
    #expect(presentation(desired: true, capitals: false) == .active(capitals: false))
    #expect(presentation(desired: true, capitals: true) == .active(capitals: true))
}

/// While Caps Lock is not CapsAwake's, capitals come from the same hardware lock as
/// sleep prevention, so the icon cannot show one axis without the other. It used to
/// read the combination's request either way and so said capitals were off while the
/// lock had them typing.
@Test func theIconShowsCapitalsWhileTheLockIsWhatProducesThem() {
    let on = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    #expect(SleepPreventionReducer.statusPresentation(for: on) == .active(capitals: true))
    #expect(SleepPreventionReducer.statusPresentation(for: SleepPreventionState()) == .idle)
}

/// The switch in the menu reads the same value, so handing the key over has to reach
/// the icon even when the change needs no other work.
@Test func handingTheKeyOverIsReportedToTheIcon() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .preferenceChanged(PreferencesSnapshot(dedicatedModeEnabled: true))
    )
    #expect(result.effects.contains(.showStatus(.active(capitals: false))))
}

/// The warning icon and the rows that explain it come from the same list, so an
/// icon the menu has nothing to say about is not a state the app can reach.
@Test func everyWarningIconHasAPermissionBehindIt() {
    let states = [
        SleepPreventionState(desired: true, sleepDisabledApplied: true),
        SleepPreventionState(privilegedError: true),
        SleepPreventionState(dedicatedFilterReady: false, dedicatedModeEnabled: true),
        SleepPreventionState(daemonNeedsApproval: true),
        SleepPreventionState(
            dedicatedFilterReady: false,
            dedicatedModeEnabled: true,
            privilegedError: true,
            daemonNeedsApproval: true
        ),
    ]
    for state in states {
        let pending = SleepPreventionReducer.systemAccess(for: state).filter(\.needsAttention)
        let isError: Bool
        if case .error = SleepPreventionReducer.statusPresentation(for: state) {
            isError = true
        } else {
            isError = false
        }
        #expect(isError == !pending.isEmpty)
    }
}

/// A daemon that was approved and still cannot write is its own failure, not a
/// second approval prompt: sending the user back to Login Items would be a
/// dead end.
@Test func anApprovedDaemonThatCannotWriteReportsAsFailing() {
    let result = SleepPreventionReducer.reduce(
        state: SleepPreventionState(desired: true, sleepDisabledApplied: true),
        intent: .sleepDisabledFailed
    )
    let daemon = SleepPreventionReducer.systemAccess(for: result.state)
        .first { $0.kind == .backgroundDaemon }
    #expect(daemon?.status == .failing)
    #expect(result.effects == [.showStatus(.error(.privileged))])
}

/// Accessibility is only asked for by the setting that needs it, so leaving
/// capitals alone must not show up as a permission the user has withheld.
@Test func accessibilityIsNotNeededWhileCapsLockStillTypesCapitals() {
    let access = SleepPreventionReducer.systemAccess(for: SleepPreventionState())
    #expect(access.first { $0.kind == .accessibility }?.status == .notNeeded)
    #expect(access.allSatisfy { !$0.needsAttention })
}

/// Turning capitals off without the grant fails closed, and the icon has to say
/// so at the moment it happens rather than at the next poll.
@Test func failingClosedOnAPreferenceChangeExplainsItself() {
    let state = SleepPreventionState(desired: true, dedicatedFilterReady: false)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .preferenceChanged(PreferencesSnapshot(dedicatedModeEnabled: true))
    )
    #expect(result.effects.contains(.showStatus(.error(.dedicatedPermission))))
}

/// A battery level means nothing while the Mac is plugged in: the reading still arrives
/// as the charge sitting in the battery, and reading it as a reason to give up would
/// switch off a Mac that is being fed.
@Test func aLowBatteryOnTheAdapterIsNotAReasonToGiveUp() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .batteryChanged(percent: 2, onBattery: false)
    )
    #expect(result.state.desired == true)
    #expect(!result.effects.contains(.notifyUser(.batteryShutdown)))
}

/// The level is a floor to be let go of *at*, not below, so the chosen level is the
/// last one CapsAwake keeps working through.
@Test func theChosenLevelIsWhereItLetsGo() {
    func desired(atPercent percent: Int) -> Bool {
        let state = SleepPreventionState(
            desired: true,
            sleepDisabledApplied: true,
            awakeBatteryFloor: 20
        )
        return SleepPreventionReducer.reduce(
            state: state,
            intent: .batteryChanged(percent: percent, onBattery: true)
        ).state.desired
    }
    #expect(desired(atPercent: 21))
    #expect(!desired(atPercent: 20))
    #expect(!desired(atPercent: 19))
}

/// A Mac with no battery reports no level, which is not a low one.
@Test func noBatteryReadingIsNotALowBattery() {
    let state = SleepPreventionState(desired: true, sleepDisabledApplied: true)
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .batteryChanged(percent: nil, onBattery: true)
    )
    #expect(result.state.desired == true)
}

/// A lid we cannot read is treated as open, so the sleep time still applies.
///
/// Stated in `shouldSleepAtSleepTime` as the safe direction: leaving a Mac awake for
/// want of a lid reading is the failure that keeps a laptop cooking in a bag, and the
/// worst an unknown lid can cost is a Mac that sleeps when the user hoped it would not.
@Test func aLidThatCannotBeReadIsTreatedAsOpen() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        clamshellClosed: nil,
        awakePastSleepTime: .whileLidClosed
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .idleObserved(seconds: 20 * 60, sleepAfterMinutes: 10, displayAsleep: true)
    )
    #expect(result.state.desired == false)
    #expect(result.effects.contains(.notifyUser(.sleepTimeReached)))
}

/// Turning the switch off after the daemon never answered emits no `.setSleepDisabled`
/// at all.
///
/// `syncSystemState` only emits it when the applied flag disagrees with what is wanted.
/// A daemon that never confirmed leaves the flag false, so switching off *agrees* with
/// it and nothing is emitted. That is correct for the daemon — there is nothing to undo
/// — but it means the effect list is not a reliable signal for anything the app does on
/// its own account. The app's own sleep assertions used to be taken and dropped here,
/// and so were never dropped: CapsAwake went on keeping the Mac awake with its switch
/// off. Anything of ours must follow `effectiveDesired`, not this effect.
@Test func turningOffAfterAFailedWriteEmitsNoSleepEffect() {
    var state = SleepPreventionState()

    state = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true)).state
    state = SleepPreventionReducer.reduce(state: state, intent: .sleepDisabledFailed).state
    #expect(state.sleepDisabledApplied == false)
    #expect(SleepPreventionReducer.effectiveDesired(state))

    let off = SleepPreventionReducer.reduce(state: state, intent: .userToggled(false))
    #expect(!SleepPreventionReducer.effectiveDesired(off.state))
    #expect(!off.effects.contains(.setSleepDisabled(false)))
    #expect(!off.effects.contains(.setSleepDisabled(true)))
}

/// The same trap on the path that fails closed: losing Accessibility while the switch is
/// on drops `effectiveDesired` without necessarily emitting a sleep effect.
@Test func failingClosedLeavesNothingForTheAppToHoldOnTo() {
    var state = SleepPreventionState(dedicatedModeEnabled: true)
    state = SleepPreventionReducer.reduce(state: state, intent: .userToggled(true)).state
    state = SleepPreventionReducer.reduce(state: state, intent: .sleepDisabledFailed).state

    let lost = SleepPreventionReducer.reduce(
        state: state,
        intent: .dedicatedFilterChanged(ready: false, enabled: true)
    )
    #expect(!SleepPreventionReducer.effectiveDesired(lost.state))
    #expect(!lost.effects.contains(.setSleepDisabled(false)))
}

// MARK: - The lock wherever the tap cannot reach

/// The event filter is what keeps a lit lock from typing capitals, and it sees
/// nothing at the lock screen — so the lock goes out there, while sleep prevention
/// itself carries on keeping the Mac awake.
@Test func theLockIsReleasedWhileTheScreenIsLocked() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: true,
        dedicatedModeEnabled: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .sessionAccessibilityChanged(SessionAccessibility(screenLocked: true))
    )
    #expect(result.effects.contains(.setCapsLockLED(false)))
    #expect(!result.effects.contains(.setSleepDisabled(false)))
    #expect(SleepPreventionReducer.effectiveDesired(result.state))
}

/// The reconcile tick re-asserts the lock every few seconds, which is exactly what
/// must not happen at a locked screen: the release has to be the target the tick
/// converges on, not a write the tick undoes.
@Test func theReconcileTickDoesNotRelightTheLockWhileTheScreenIsLocked() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: false,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(screenLocked: true)
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .reconcileTick)
    #expect(!result.effects.contains(.setCapsLockLED(true)))
}

@Test func theLockIsRestoredWhenTheScreenUnlocks() {
    let locked = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: false,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(screenLocked: true)
    )
    let unlocked = SleepPreventionReducer.reduce(
        state: locked,
        intent: .sessionAccessibilityChanged(SessionAccessibility())
    )
    #expect(unlocked.effects.contains(.setCapsLockLED(true)))

    // With the switch off there is nothing to restore.
    let idle = SleepPreventionState(
        capsLockLEDOn: false,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(screenLocked: true)
    )
    let stillOff = SleepPreventionReducer.reduce(
        state: idle,
        intent: .sessionAccessibilityChanged(SessionAccessibility())
    )
    #expect(!stillOff.effects.contains(.setCapsLockLED(true)))
}

/// Secure input takes the keyboard away from the tap without the screen locking —
/// a password field — and a lit lock would type the password in capitals.
@Test func secureInputReleasesTheLockWithoutTouchingSleepPrevention() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: true,
        dedicatedModeEnabled: true
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .sessionAccessibilityChanged(SessionAccessibility(secureInputActive: true))
    )
    #expect(result.effects.contains(.setCapsLockLED(false)))
    #expect(!result.effects.contains(.setSleepDisabled(false)))
}

/// While the session is out of reach the key is a plain Caps Lock, and a press is
/// someone typing at a password field. The lock is left wherever they put it, and
/// nothing reads it as the switch.
@Test func aCapsLockPressAtTheLoginWindowIsNotTheSwitch() {
    let state = SleepPreventionState(
        capsLockLEDOn: false,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(sessionActive: false)
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .externalCapsLockChanged(true)
    )
    #expect(result.state.desired == false)
    #expect(result.state.capsLockLEDOn == true)
    #expect(result.effects.isEmpty)
}

/// Switching input sources clears the hardware lock, and the correcting write must
/// not put it back where the release just took it out.
@Test func anInputSourceChangeWhileTheScreenIsLockedLeavesTheLockOut() {
    let state = SleepPreventionState(
        desired: true,
        capsLockLEDOn: false,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(screenLocked: true)
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .inputSourceChanged)
    #expect(result.effects.isEmpty)
}

/// Without Dedicated Mode there is no filter, and the lit lock is honest caps typing
/// — exactly what a hardware Caps Lock does at a locked screen — so it stays.
@Test func withoutDedicatedModeTheLockStaysWithSleepPrevention() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        capsLockLEDOn: true,
        dedicatedModeEnabled: false
    )
    let result = SleepPreventionReducer.reduce(
        state: state,
        intent: .sessionAccessibilityChanged(SessionAccessibility(screenLocked: true))
    )
    #expect(!result.effects.contains(.setCapsLockLED(false)))
}

/// Launching behind a locked screen — a login item racing the unlock — must not
/// light the lock before the session is there to strip what it implies.
@Test func startupWhileLockedDoesNotLightTheLock() {
    let state = SleepPreventionState(
        desired: true,
        sleepDisabledApplied: true,
        dedicatedModeEnabled: true,
        session: SessionAccessibility(screenLocked: true)
    )
    let result = SleepPreventionReducer.reduce(state: state, intent: .startup)
    #expect(!result.effects.contains(.setCapsLockLED(true)))
}
