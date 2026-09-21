import CapsAwakeCore
import Foundation
import IOKit
import IOKit.pwr_mgt
import os

public final class PrivilegedPowerController: @unchecked Sendable {
    public static let shared = PrivilegedPowerController()

    private static let log = Logger(subsystem: AppIdentity.osLogSubsystem, category: "privileged")

    private let lock = NSLock()
    private var clientRequestedDisabled = false
    private var assertionID: IOPMAssertionID = 0
    private let baseline = PrivilegedBaselineStore.shared

    private init() {}

    public func readSleepDisabled() -> Bool? {
        let result = PmsetCommand.run(arguments: ["-g"])
        guard result.status == 0 else { return nil }
        return PmsetCommand.parseSleepDisabled(from: result.stdout)
    }

    /// Disables sleep, or puts back whatever the machine had before CapsAwake first
    /// disabled it.
    ///
    /// The value to go back to is recorded on disk before the first write and cleared
    /// once it has been restored, so a daemon that is replaced or killed mid-override
    /// does not come back and mistake our own setting for the user's.
    public func setSleepDisabled(_ disabled: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        clientRequestedDisabled = disabled
        updateAssertion(on: disabled)

        guard disabled else { return restoreSleepDisabled() }

        if baseline.sleepDisabled() == nil {
            // An unreadable setting is recorded as "sleep was working", because the
            // failure that follows from guessing wrong that way is a Mac that sleeps
            // normally, and the other way it is a Mac that never sleeps again.
            guard baseline.recordSleepDisabled(readSleepDisabled() ?? false) else {
                Self.log.error("Refusing to disable sleep: the baseline could not be recorded")
                return false
            }
        }
        return write(sleepDisabled: true)
    }

    /// Puts `SleepDisabled` back to the recorded baseline and forgets it. A no-op
    /// when nothing was recorded, so callers need not track whether they overrode it.
    private func restoreSleepDisabled() -> Bool {
        guard let recorded = baseline.sleepDisabled() else { return true }
        guard write(sleepDisabled: recorded) else { return false }
        baseline.clearSleepDisabled()
        return true
    }

    /// Writes the setting and reads it back, because `pmset` exits 0 either way.
    private func write(sleepDisabled: Bool) -> Bool {
        let result = PmsetCommand.run(arguments: ["-a", "disablesleep", sleepDisabled ? "1" : "0"])
        guard result.status == 0 else { return false }
        return readSleepDisabled() == sleepDisabled
    }

    public func restoreBaselineIfNoClient() {
        lock.lock()
        let shouldRestore = !clientRequestedDisabled
        lock.unlock()
        guard shouldRestore else { return }
        _ = setSleepDisabled(false)
        _ = restoreEnergyMode()
    }

    /// Drop the client's request and restore the baseline sleep setting.
    ///
    /// Used when the last XPC client disconnects. Unlike
    /// `restoreBaselineIfNoClient`, this clears `clientRequestedDisabled` so a
    /// previous `setSleepDisabled(true)` cannot keep the machine awake forever.
    public func abandonClientRequest() {
        lock.lock()
        clientRequestedDisabled = false
        lock.unlock()
        _ = setSleepDisabled(false)
        _ = restoreEnergyMode()
    }

    /// Imposes `plan`, recording what each power source had first.
    ///
    /// Only power sources this Mac reports are written, and each write is verified,
    /// so a mode the hardware refuses on one source (High Power on battery, for
    /// instance) is reported as a failure without disturbing the other.
    public func overrideEnergyMode(_ plan: EnergyModePlan) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let current = EnergyModeSettings.current()
        guard !current.isEmpty else { return false }

        // Record the baseline before the first write only. After a crash the stored
        // values are the user's and the live ones are ours. A baseline that cannot be
        // written is a refusal rather than a warning: an Energy Mode nobody can put
        // back is worse than one that was never changed.
        guard baseline.recordEnergyModes(current) else {
            Self.log.error("Refusing to change the Energy Mode: the baseline could not be recorded")
            return false
        }

        var applied = true
        for (source, mode) in current {
            let target = plan.mode(for: source)
            guard mode != target else { continue }
            if !EnergyModeSettings.apply(target, to: source) {
                applied = false
            }
        }
        return applied
    }

    /// Puts every power source back to its recorded baseline.
    ///
    /// A missing baseline means CapsAwake never changed the mode, so this is a
    /// no-op that callers can make unconditionally.
    public func restoreEnergyMode() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let recorded = baseline.energyModes() else { return true }
        var restored = true
        for (source, mode) in recorded {
            if !EnergyModeSettings.apply(mode, to: source) {
                restored = false
            }
        }
        // Keep the baseline when a write failed so a later attempt can still finish.
        if restored {
            baseline.clearEnergyModes()
        }
        return restored
    }

    private func updateAssertion(on: Bool) {
        if on {
            guard assertionID == 0 else { return }
            var newID: IOPMAssertionID = 0
            let reason = "CapsAwake" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
            }
        } else if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
