import Foundation
import IOKit.ps

/// What the Mac is running on, and how much of it is left.
public struct PowerSourceReading: Equatable, Sendable {
    /// Charge remaining, as a percentage. `nil` on a Mac with no battery.
    public let percent: Int?
    public let onBattery: Bool

    public init(percent: Int?, onBattery: Bool) {
        self.percent = percent
        self.onBattery = onBattery
    }
}

/// Reads the built-in battery and whether the adapter is in.
public enum PowerSourceReader {
    public static func read() -> PowerSourceReading? {
        guard
            let sources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() as? [[String: Any]],
            let source = internalBattery(in: sources) ?? sources.first,
            let powerSource = source[kIOPSPowerSourceStateKey] as? String
        else {
            return nil
        }
        return PowerSourceReading(
            percent: source[kIOPSCurrentCapacityKey] as? Int,
            onBattery: powerSource != kIOPSACPowerValue
        )
    }

    /// The Mac's own battery, rather than whichever power source happens to be listed
    /// first. A UPS or an attached device that reports itself as a power source would
    /// otherwise be read as the machine's battery, and the level CapsAwake releases
    /// sleep prevention at would be somebody else's.
    private static func internalBattery(in sources: [[String: Any]]) -> [String: Any]? {
        sources.first { $0[kIOPSTransportTypeKey] as? String == kIOPSInternalType }
    }
}
