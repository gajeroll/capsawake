import Foundation
import IOKit

/// Reads properties off `IOPMrootDomain`, where macOS keeps the machine's power
/// state and the settings that govern it.
enum RootDomain {
    static func boolProperty(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let value = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }
        return (value as? NSNumber)?.boolValue
    }
}
