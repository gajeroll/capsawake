import Foundation
import IOKit

/// How long the keyboard and pointer have gone untouched, as macOS itself counts it.
///
/// The same clock the system's idle sleep runs on, so CapsAwake standing aside at
/// the sleep time means standing aside at the moment the Mac would have slept.
/// Reading it costs an IORegistry lookup and needs no permission, and nothing
/// CapsAwake does to the keyboard — writing the LED, stripping a modifier — counts
/// as input, so only a real touch of the keyboard restarts it.
public enum InputIdleTime {
    public static func seconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let value = IORegistryEntryCreateCFProperty(
                service,
                "HIDIdleTime" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
            let nanoseconds = (value as? NSNumber)?.doubleValue
        else {
            return nil
        }
        return nanoseconds / 1_000_000_000
    }
}
