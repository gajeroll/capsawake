import Foundation
import IOKit

/// Reads and removes the delay macOS applies before the Caps Lock key engages.
///
/// A press shorter than the delay — 75 ms on a stock keyboard — moves nothing. The
/// lock stays where it was, so no `flagsChanged` event is generated and no event tap
/// of any kind can see that the key was touched: a fast tap of the switch is lost
/// before CapsAwake has any say in it. The delay is there to keep a brush of the key
/// from turning on capitals, which is not what the key is for while CapsAwake is
/// running, so CapsAwake can take it out.
///
/// The delay belongs to the keyboard rather than to us, so the value it came with is
/// read before anything is imposed and written back when CapsAwake quits.
public enum CapsLockDelaySettings {
    /// What macOS ships with, used when the keyboard reports nothing of its own.
    public static let stockDelay = 75

    static let overrideProperty = "CapsLockDelayOverride"
    private static let deviceProperty = "CapsLockDelay"
    private static let servicePropertiesKey = "HIDEventServiceProperties"
    private static let hidutilPath = "/usr/bin/hidutil"
    /// Keyboards, by HID usage page 1 (generic desktop) usage 6 (keyboard).
    private static let keyboardMatching = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#

    /// The delay this keyboard came with, in milliseconds.
    ///
    /// Read from the I/O registry because `hidutil` reports this property as null.
    /// The registry keeps the keyboard's own value next to the override rather than
    /// under it, so this is still the value to go back to once one is in place.
    public static func deviceDelay() -> Int {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOHIDEventService"),
                &iterator
            ) == KERN_SUCCESS
        else { return stockDelay }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return stockDelay }
            defer { IOObjectRelease(service) }
            let properties =
                IORegistryEntryCreateCFProperty(
                    service,
                    servicePropertiesKey as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any]
            // Only a keyboard carries the property, so the first service to report it
            // is one and there is nothing to choose between several of them.
            if let delay = properties?[deviceProperty] as? Int { return delay }
        }
    }

    /// Writes the delay every keyboard should use and reads it back, because
    /// `hidutil` exits 0 for a property nothing took.
    ///
    /// Overrides live in the I/O registry rather than on disk, so they are gone after
    /// a restart whatever happens to this process.
    public static func apply(delay: Int) -> Bool {
        let result = run(["--set", "{\"\(overrideProperty)\":\(delay)}"])
        guard result.status == 0 else { return false }
        let applied = currentDelays()
        return !applied.isEmpty && applied.allSatisfy { $0 == delay }
    }

    /// The delay in force on each keyboard, in milliseconds.
    public static func currentDelays() -> [Int] {
        let result = run(["--get", overrideProperty])
        guard result.status == 0 else { return [] }
        return parseValues(from: result.stdout, key: overrideProperty)
    }

    private static func run(_ arguments: [String]) -> SystemCommand.Result {
        SystemCommand.run(hidutilPath, ["property", "--matching", keyboardMatching] + arguments)
    }

    /// `hidutil` prints a header row and then one row per service, whose value is
    /// `(null)` for a service that does not carry the property.
    static func parseValues(from output: String, key: String) -> [Int] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3, fields[1] == key else { return nil }
            return Int(fields[2])
        }
    }
}
