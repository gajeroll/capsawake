import CapsAwakeCore
import Foundation

/// The Mac's own "put the Mac to sleep after N minutes", per power source.
///
/// CapsAwake normally makes this moot: `SleepDisabled` stops the timer being
/// consulted at all. It is read so the setting can be honoured on purpose — the
/// user asking CapsAwake to stand aside once the Mac would have slept by itself —
/// and so Settings can say what that time currently is.
public enum SystemSleepTimer {
    /// Minutes of no input before macOS would sleep. Zero is how macOS says never,
    /// and a missing entry means the reading failed.
    ///
    /// Forks `pmset`, so callers keep the result rather than asking every tick.
    public static func minutes() -> [PowerSource: Int] {
        let result = PmsetCommand.run(arguments: ["-g", "custom"])
        guard result.status == 0 else { return [:] }
        return parseMinutes(from: result.stdout)
    }

    static func parseMinutes(from output: String) -> [PowerSource: Int] {
        var minutes: [PowerSource: Int] = [:]
        var section: PowerSource?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasSuffix(":") {
                let title = String(trimmed.dropLast())
                section = PowerSource.allCases.first { $0.pmsetSectionTitle == title }
                continue
            }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            // `displaysleep` and `disksleep` are timers of their own, and "Sleep On
            // Power Button" is not a timer at all, so match the key exactly and
            // require a number after it.
            guard let section,
                fields.count >= 2,
                fields[0] == "sleep",
                let value = Int(fields[1])
            else { continue }
            minutes[section] = value
        }
        return minutes
    }
}
