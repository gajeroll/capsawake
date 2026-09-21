import Foundation
import IOKit
import IOKit.pwr_mgt

/// The power assertions CapsAwake holds while sleep prevention is on.
///
/// These are what `caffeinate` takes, and they are not the whole story: macOS ignores
/// assertions once the lid is closed, which is what the daemon's `SleepDisabled` is
/// for. They earn their place anyway. The app holds them itself, so idle sleep is
/// still blocked while the daemon is being replaced or has died, and
/// `PreventSystemSleep` is the assertion meant for work that should carry on with the
/// display off — the case CapsAwake exists for.
public final class SleepAssertions {
    /// Kept together because they are taken and dropped as one.
    private static let types = [
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionTypePreventSystemSleep,
    ]

    private let name = "CapsAwake sleep prevention" as CFString
    private var ids: [IOPMAssertionID] = []

    public init() {}

    deinit {
        for id in ids {
            IOPMAssertionRelease(id)
        }
    }

    public var isHeld: Bool { !ids.isEmpty }

    /// Idempotent, so callers can follow the switch rather than track the difference.
    public func hold(_ shouldHold: Bool) {
        guard shouldHold != isHeld else { return }
        guard shouldHold else {
            for id in ids {
                IOPMAssertionRelease(id)
            }
            ids = []
            return
        }

        for type in Self.types {
            var id: IOPMAssertionID = 0
            let created = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name,
                &id
            )
            if created == kIOReturnSuccess {
                ids.append(id)
            }
        }
    }
}
