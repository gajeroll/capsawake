import Foundation
import IOKit
import IOKit.pwr_mgt

enum PmsetCommand {
    static func run(arguments: [String]) -> SystemCommand.Result {
        SystemCommand.run("/usr/bin/pmset", arguments)
    }

    static func parseSleepDisabled(from output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                fields[0].lowercased() == "sleepdisabled"
            else { continue }
            switch fields[1] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        return nil
    }
}

public enum PowerSettingsReader {
    /// Whether sleep is disabled machine-wide, read straight from IOKit.
    ///
    /// This is the same `SleepDisabled` that `pmset -g` prints, without forking it:
    /// cheap enough to check on every reconcile tick, which is what lets the app
    /// notice that something else put the setting back.
    public static func sleepDisabled() -> Bool? {
        RootDomain.boolProperty("SleepDisabled")
    }
}

/// Asks macOS to sleep the displays now, as the Control Center sleep action does.
///
/// `pmset displaysleepnow` needs no root — unlike `disablesleep` — so this runs in
/// the app rather than being one more thing the root daemon can be asked to do, and
/// it keeps working while the daemon cannot run at all. Forks `pmset`, so callers
/// should stay off the main actor.
public enum DisplaySleeper {
    public static func requestNow() -> Bool {
        PmsetCommand.run(arguments: ["displaysleepnow"]).status == 0
    }
}
