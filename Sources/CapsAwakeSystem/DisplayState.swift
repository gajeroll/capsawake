import CoreGraphics
import Foundation
import IOKit

public enum ClamshellReader {
    public static func isClosed() -> Bool? {
        boolProperty("AppleClamshellState")
    }

    /// Whether closing the lid would put the Mac to sleep right now.
    ///
    /// IOKit can report Yes even when `SleepDisabled` is set, so treat this as an
    /// advisory signal rather than proof that sleep prevention failed.
    public static func causesSleep() -> Bool? {
        boolProperty("AppleClamshellCausesSleep")
    }

    private static func boolProperty(_ key: String) -> Bool? {
        RootDomain.boolProperty(key)
    }
}

/// Whether the display is asleep right now, as CoreGraphics reports the active one.
///
/// macOS never idle-sleeps the system while a display is on — powerd holds an
/// assertion saying exactly that — so the moment the Mac would have slept by itself
/// can only ever arrive after this reads true.
public enum DisplayPowerReader {
    public static func isAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }
}

public enum ExternalDisplayReader {
    public static func isConnected() -> Bool? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
            return nil
        }
        guard displayCount > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }
        return displays.prefix(Int(displayCount)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
