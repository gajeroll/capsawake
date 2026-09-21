import Testing

@testable import CapsAwakeCore

/// The store exists to make one thing impossible: changing state without going through
/// an intent. Everything the app observes about the Mac — the lid, the LED, the
/// battery — arrives here as an intent, and the reducer decides what it means.

@MainActor
@Test func stateOnlyMovesThroughAnIntent() {
    let store = SleepPreventionStore { _ in }
    #expect(!store.state.desired)

    store.dispatch(.userToggled(true))
    #expect(store.state.desired)
}

@MainActor
@Test func effectsReachTheAppThatHasToCarryThemOut() {
    var performed: [[Effect]] = []
    let store = SleepPreventionStore { performed.append($0) }

    store.dispatch(.userToggled(true))

    #expect(performed.count == 1)
    #expect(performed.first?.contains(.setSleepDisabled(true)) == true)
}

/// An intent that decides nothing must not call out to the app at all. The reconcile
/// tick runs every five seconds, and a store that performed an empty list each time
/// would wake the whole effect path for nothing.
@MainActor
@Test func anIntentThatChangesNothingPerformsNothing() {
    var calls = 0
    let store = SleepPreventionStore { _ in calls += 1 }

    store.dispatch(.capsLockLEDObserved(nil))

    #expect(calls == 0)
}

/// The store starts from where it is told to, which is what lets a test set up a Mac
/// in a particular state without replaying the intents that would have got it there.
@MainActor
@Test func theStoreStartsFromTheStateItIsGiven() {
    let store = SleepPreventionStore(
        initial: SleepPreventionState(desired: true, sleepDisabledApplied: true),
        perform: { _ in }
    )
    #expect(store.state.desired)
    #expect(store.state.sleepDisabledApplied)
}

/// Each dispatch sees what the last one left behind, rather than the state the store
/// was built with.
@MainActor
@Test func intentsAccumulate() {
    let store = SleepPreventionStore { _ in }

    store.dispatch(.userToggled(true))
    store.dispatch(.batteryChanged(percent: 80, onBattery: true))

    #expect(store.state.desired)
    #expect(store.state.batteryPercent == 80)
    #expect(store.state.onBattery)
}
