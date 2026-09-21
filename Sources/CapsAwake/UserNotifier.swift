import CapsAwakeCore
import CapsAwakeSystem
import CapsAwakeUI
import Foundation
import UserNotifications

/// Says the things the menu bar icon cannot.
///
/// Two kinds of message end up here. The switch turning itself off — too hot, too
/// little battery left, the Mac's own sleep time reached — always warrants one, because
/// the user asked for something and is no longer getting it. And a permission that has
/// gone missing warrants one only when the menu bar icon is hidden, since with the icon
/// gone there is nowhere else to put a warning badge.
@MainActor
final class UserNotifier {
    /// Fires once per stretch of being blocked, rather than on every reconcile tick
    /// that notices the same thing.
    private var didWarnAboutHiddenError = false

    /// The user's chosen language rather than the system's, so a notification reads
    /// like the rest of the app.
    private var locale: Locale {
        Locale(identifier: UserPreferences.language.rawValue)
    }

    func notify(_ kind: NotificationKind) async {
        let body: String
        switch kind {
        case .thermalShutdown:
            body = NotificationStrings.thermalShutdown(locale: locale)
        case .batteryShutdown:
            body = NotificationStrings.batteryShutdown(locale: locale)
        case .sleepTimeReached:
            body = NotificationStrings.sleepTimeReached(locale: locale)
        case .displaySleepBlocked:
            body = NotificationStrings.displaySleepBlocked(
                blockers: DisplaySleepBlockers.processNames(),
                locale: locale
            )
        }
        await post(body: body)
    }

    /// With the menu bar icon hidden there is nowhere to show a warning badge, so fall
    /// back to a notification.
    func warnIfBlockedWhileHidden(_ presentation: StatusPresentation) {
        let body: String? =
            switch presentation {
            case .error(.dedicatedPermission):
                NotificationStrings.accessibilityRequired(locale: locale)
            case .error(.daemonApproval):
                NotificationStrings.daemonApprovalRequired(locale: locale)
            default:
                nil
            }
        guard let body, !UserPreferences.showMenuBarIcon else {
            didWarnAboutHiddenError = false
            return
        }
        guard !didWarnAboutHiddenError else { return }
        didWarnAboutHiddenError = true
        Task { await post(body: body) }
    }

    private func post(body: String) async {
        let content = UNMutableNotificationContent()
        content.title = AppIdentity.name
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        try? await UNUserNotificationCenter.current().add(request)
    }
}
