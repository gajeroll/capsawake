import ApplicationServices
import Foundation

/// Accessibility (`AXIsProcessTrusted`) checks for the Caps Lock event tap.
///
/// macOS grants the permission out of band, so callers should poll `isTrusted`
/// rather than assume the answer from launch time is final.
public enum AccessibilityPermission {
    /// Current trust state. Never shows UI, so it is safe to poll.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Same check, but asks macOS to show the system permission prompt.
    /// macOS shows it at most once per app version, so calling this repeatedly
    /// is harmless but pointless.
    @discardableResult
    public static func prompt() -> Bool {
        // The literal key avoids `kAXTrustedCheckOptionPrompt`, whose
        // CoreServices global is not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
