import Darwin
import Foundation
import IOKit.pwr_mgt

/// Names processes that currently hold a display-sleep assertion.
///
/// Readable without root. Used to explain why a lid-close display-sleep request
/// did not stick (e.g. a browser holding `NoDisplaySleepAssertion` for video).
public enum DisplaySleepBlockers {
    public static func processNames() -> [String] {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
            let dictionary = assertions?.takeRetainedValue() as? [Int: [[String: Any]]]
        else {
            return []
        }

        var names: [String] = []
        var seen = Set<String>()
        for (pid, entries) in dictionary {
            for entry in entries {
                guard let type = entry[kIOPMAssertionTypeKey] as? String,
                    isDisplaySleepAssertion(type)
                else { continue }
                let name = processName(pid: pid) ?? "pid \(pid)"
                if seen.insert(name).inserted {
                    names.append(name)
                }
            }
        }
        return names.sorted()
    }

    private static func isDisplaySleepAssertion(_ type: String) -> Bool {
        type == kIOPMAssertionTypeNoDisplaySleep
            || type == kIOPMAssertionTypePreventUserIdleDisplaySleep
    }

    private static func processName(pid: Int) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid_t(pid), &path, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        let bytes = path.prefix(Int(length)).map(UInt8.init)
        let fullPath = String(decoding: bytes, as: UTF8.self)
        return URL(fileURLWithPath: fullPath).lastPathComponent
    }
}
