import Foundation

/// Notification copy lives in this module so it resolves from the String Catalog,
/// and takes an explicit locale so it follows the Language preference rather than
/// the system locale.
public enum NotificationStrings {
    public static func thermalShutdown(locale: Locale) -> String {
        String(localized: "notification_thermal", locale: locale)
    }

    public static func batteryShutdown(locale: Locale) -> String {
        String(localized: "notification_battery", locale: locale)
    }

    public static func sleepTimeReached(locale: Locale) -> String {
        String(localized: "notification_sleep_time", locale: locale)
    }

    public static func accessibilityRequired(locale: Locale) -> String {
        String(localized: "notification_accessibility", locale: locale)
    }

    public static func daemonApprovalRequired(locale: Locale) -> String {
        String(localized: "notification_daemon_approval", locale: locale)
    }

    public static func displaySleepBlocked(blockers: [String], locale: Locale) -> String {
        let base = String(localized: "notification_display_sleep_blocked", locale: locale)
        guard !blockers.isEmpty else { return base }
        let joined = blockers.joined(separator: ", ")
        return "\(base) (\(joined))"
    }
}
