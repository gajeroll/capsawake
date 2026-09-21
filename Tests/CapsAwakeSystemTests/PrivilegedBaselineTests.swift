import CapsAwakeCore
import Foundation
import Testing

@testable import CapsAwakeSystem

/// A store in a temporary directory of its own, so nothing here touches the machine's
/// real baseline and nothing needs root.
private func withStore(_ body: (PrivilegedBaselineStore) throws -> Void) rethrows {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "capsawake-baseline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false))
}

@Test func nothingIsRecordedUntilSomethingIsOverridden() {
    withStore { store in
        #expect(store.sleepDisabled() == nil)
        #expect(store.energyModes() == nil)
    }
}

@Test func theRecordedSleepSettingSurvivesANewStore() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "capsawake-baseline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(writer.recordSleepDisabled(false))

    // A fresh process — which is what a relaunched daemon is.
    let reader = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(reader.sleepDisabled() == false)
}

/// The regression this file exists for.
///
/// The daemon is demand-launched and exits with its last client, so it can die while
/// `SleepDisabled` is still set — a crash, a kill, a forced power-off. The baseline
/// used to live in memory, so the next daemon read CapsAwake's own override as the
/// value to go back to and the Mac never slept again. The first recording is the only
/// one that counts, and it outlives the process.
@Test func aRelaunchedDaemonDoesNotAdoptOurOwnOverrideAsTheBaseline() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "capsawake-baseline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(first.recordSleepDisabled(false))

    // The daemon dies here with sleep still disabled, and a new one comes up and
    // tries to record what it now reads off the machine: our own `true`.
    let relaunched = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(relaunched.recordSleepDisabled(true))

    #expect(relaunched.sleepDisabled() == false)
}

@Test func aRestoredSettingIsForgotten() {
    withStore { store in
        #expect(store.recordSleepDisabled(true))
        store.clearSleepDisabled()
        #expect(store.sleepDisabled() == nil)
    }
}

/// The two baselines are independent: restoring one must not lose the other, because
/// the switch goes off before the app quits and the Energy Mode is put back separately.
@Test func clearingOneBaselineLeavesTheOther() {
    withStore { store in
        #expect(store.recordSleepDisabled(true))
        #expect(store.recordEnergyModes([.battery: .automatic, .adapter: .high]))

        store.clearSleepDisabled()
        #expect(store.sleepDisabled() == nil)
        #expect(store.energyModes() == [.battery: .automatic, .adapter: .high])

        store.clearEnergyModes()
        #expect(store.energyModes() == nil)
    }
}

@Test func theEnergyModeBaselineIsRecordedOnceAndSurvives() {
    withStore { store in
        #expect(store.recordEnergyModes([.battery: .automatic]))
        // What CapsAwake imposed, offered as a baseline by a relaunched daemon.
        #expect(store.recordEnergyModes([.battery: .low]))
        #expect(store.energyModes() == [.battery: .automatic])
    }
}

/// Upgrading from a version that only recorded the Energy Mode must not lose the mode
/// to go back to.
@Test func aBaselineFromTheOldFormatIsCarriedOver() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "capsawake-baseline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let legacy = try PropertyListEncoder().encode(["battery": "automatic", "adapter": "low"])
    try legacy.write(to: directory.appending(path: "energy-mode-baseline.plist"))

    let store = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(store.energyModes() == [.battery: .automatic, .adapter: .low])

    // Carried over rather than read in place, so the old file goes.
    #expect(
        !FileManager.default.fileExists(
            atPath: directory.appending(path: "energy-mode-baseline.plist").path
        )
    )
    #expect(
        FileManager.default.fileExists(atPath: directory.appending(path: "baseline.plist").path)
    )
}

/// `/Library/Application Support` is writable by admin users, so the daemon must not
/// be steerable by a symlink left where its baseline goes.
@Test func aSymlinkedBaselineIsNotRead() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "capsawake-baseline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let elsewhere = directory.appending(path: "planted.plist")
    try PropertyListEncoder().encode(["battery": "high"]).write(to: elsewhere)
    try FileManager.default.createSymbolicLink(
        at: directory.appending(path: "energy-mode-baseline.plist"),
        withDestinationURL: elsewhere
    )

    let store = PrivilegedBaselineStore(directory: directory, requiresRootOwnership: false)
    #expect(store.energyModes() == nil)
}
