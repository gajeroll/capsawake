import CapsAwakeCore
import Testing

@testable import CapsAwake

/// `UserDefaults.didChangeNotification` fires for every key and says nothing about
/// which one moved, so the app compares snapshots. What matters is that the comparison
/// is total: a preference the diff forgets is a preference whose reaction never runs,
/// and the symptom is a setting that appears to do nothing until the next launch.

/// Built rather than read: these assert what the diff does, not what this Mac's
/// `UserDefaults` happens to hold while the tests run.
private func snapshot(_ edit: (inout PreferenceSnapshot) -> Void) -> PreferenceSnapshot {
    var snapshot = PreferenceSnapshot()
    edit(&snapshot)
    return snapshot
}

@Test func anUnchangedSnapshotIsNotAChange() {
    let before = PreferenceSnapshot()
    #expect(PreferenceChange.between(before, before).isEmpty)
}

@Test func handingTheKeyOverIsNoticed() {
    let before = snapshot { $0.dedicatedMode = false }
    let after = snapshot { $0.dedicatedMode = true }
    let changes = PreferenceChange.between(before, after)
    #expect(changes.contains(.dedicatedMode))
    // It also decides where capitals come from, which the state machine renders.
    #expect(changes.contains(.reducerInput))
}

@Test func theCapitalsCombinationIsNoticed() {
    let before = snapshot { $0.capitalsModifiers = .shift }
    let after = snapshot { $0.capitalsModifiers = [.control, .option] }
    #expect(PreferenceChange.between(before, after) == [.capitalsModifiers])
}

@Test func theShiftSmallLetterSettingIsNoticed() {
    let before = snapshot { $0.shiftTypesSmallLetters = false }
    let after = snapshot { $0.shiftTypesSmallLetters = true }
    #expect(PreferenceChange.between(before, after) == [.shiftTypesSmallLetters])
}

@Test func theCapsLockDelayIsNoticed() {
    let before = snapshot { $0.removeCapsLockDelay = true }
    let after = snapshot { $0.removeCapsLockDelay = false }
    #expect(PreferenceChange.between(before, after) == [.capsLockDelay])
}

@Test func launchAtLoginIsNoticed() {
    let before = snapshot { $0.launchAtLogin = true }
    let after = snapshot { $0.launchAtLogin = false }
    #expect(PreferenceChange.between(before, after) == [.launchAtLogin])
}

/// Everything the reducer reads has to reach it, or the setting silently does nothing.
@Test func everySettingTheStateMachineReadsReachesIt() {
    let base = PreferenceSnapshot()

    let lid = snapshot { $0.displaySleepOnLidClose = !base.displaySleepOnLidClose }
    #expect(PreferenceChange.between(base, lid).contains(.reducerInput))

    let energy = snapshot { $0.energyModePlan = EnergyModePlan(.high) }
    #expect(PreferenceChange.between(base, energy).contains(.reducerInput))

    let sleepTime = snapshot { $0.awakePastSleepTime = .never }
    #expect(PreferenceChange.between(base, sleepTime).contains(.reducerInput))

    let floor = snapshot { $0.awakeBatteryFloor = 40 }
    #expect(PreferenceChange.between(base, floor).contains(.reducerInput))

    // "Any level" is stored as no level at all, which is a change like any other.
    let noFloor = snapshot { $0.awakeBatteryFloor = nil }
    #expect(PreferenceChange.between(base, noFloor).contains(.reducerInput))
}

/// One preference moving must not be reported as all of them moving, or the diff has
/// bought nothing over reacting to the bare notification.
@Test func onlyWhatMovedIsReported() {
    let before = PreferenceSnapshot(launchAtLogin: true)
    let after = snapshot { $0.launchAtLogin = false }
    let changes = PreferenceChange.between(before, after)
    #expect(!changes.contains(.dedicatedMode))
    #expect(!changes.contains(.capitalsModifiers))
    #expect(!changes.contains(.capsLockDelay))
    #expect(!changes.contains(.reducerInput))
}
