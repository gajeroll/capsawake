import CapsAwakeCore
import Foundation

extension EnergyMode {
    /// The `pmset powermode` value. 0 is what System Settings calls Automatic.
    var powerModeValue: Int {
        switch self {
        case .automatic: 0
        case .low: 1
        case .high: 2
        }
    }

    init?(powerModeValue: Int) {
        switch powerModeValue {
        case 0: self = .automatic
        case 1: self = .low
        case 2: self = .high
        default: return nil
        }
    }
}

extension PowerSource {
    var pmsetFlag: String {
        switch self {
        case .battery: "-b"
        case .adapter: "-c"
        }
    }

    /// The section header `pmset -g custom` prints for this source, lowercased.
    var pmsetSectionTitle: String {
        switch self {
        case .battery: "battery power"
        case .adapter: "ac power"
        }
    }
}

/// Reads and writes the Energy Mode through `pmset powermode`.
///
/// Writes need root, so only the daemon calls `apply`; reading capabilities and
/// current values works unprivileged.
public enum EnergyModeSettings {
    /// The modes this Mac offers, or an empty set when it has no Energy Mode.
    ///
    /// `pmset -g cap` reports the capabilities of the *current* power source and
    /// ignores `-b`/`-c`, so High Power can come and go as the adapter is plugged
    /// in. Callers refresh this when the power source changes.
    public static func supportedModes() -> Set<EnergyMode> {
        let capabilities = PmsetCommand.run(arguments: ["-g", "cap"])
        guard capabilities.status == 0 else { return [] }
        let modes = parseSupportedModes(from: capabilities.stdout)
        guard !modes.isEmpty else { return [] }
        // Older Macs advertise `lowpowermode` but keep the setting under a
        // different key, so require the key we actually write.
        guard !current().isEmpty else { return [] }
        return modes
    }

    public static func current() -> [PowerSource: EnergyMode] {
        let result = PmsetCommand.run(arguments: ["-g", "custom"])
        guard result.status == 0 else { return [:] }
        return parseModes(from: result.stdout)
    }

    /// Writes one power source's mode and reads it back, because `pmset` exits 0
    /// for a mode the hardware will not take.
    public static func apply(_ mode: EnergyMode, to source: PowerSource) -> Bool {
        let result = PmsetCommand.run(
            arguments: [source.pmsetFlag, "powermode", String(mode.powerModeValue)]
        )
        guard result.status == 0 else { return false }
        return current()[source] == mode
    }

    static func parseSupportedModes(from output: String) -> Set<EnergyMode> {
        var modes: Set<EnergyMode> = []
        for line in output.split(whereSeparator: \.isNewline) {
            switch line.trimmingCharacters(in: .whitespaces).lowercased() {
            case "lowpowermode": modes.formUnion([.automatic, .low])
            case "highpowermode": modes.insert(.high)
            default: continue
            }
        }
        // High Power without the baseline modes would be a nonsense reading.
        return modes.contains(.low) ? modes : []
    }

    static func parseModes(from output: String) -> [PowerSource: EnergyMode] {
        var modes: [PowerSource: EnergyMode] = [:]
        var section: PowerSource?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasSuffix(":") {
                let title = String(trimmed.dropLast())
                section = PowerSource.allCases.first { $0.pmsetSectionTitle == title }
                continue
            }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            // `lowpowermode` on Intel Macs is a different setting, so match exactly.
            guard let section,
                fields.count >= 2,
                fields[0] == "powermode",
                let value = Int(fields[1]),
                let mode = EnergyMode(powerModeValue: value)
            else { continue }
            modes[section] = mode
        }
        return modes
    }
}
