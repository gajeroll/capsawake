import CapsAwakeCore
import SwiftUI

/// How each permission is worded and drawn.
///
/// Kept in one place because the same item appears in three sizes: a line in the
/// menu, a full row in Settings, and a step during onboarding. They differ in how
/// much they show, never in what they say.
extension SystemAccessItem {
    var titleKey: LocalizedStringKey {
        switch kind {
        case .backgroundDaemon: "access_daemon_title"
        case .accessibility: "access_accessibility_title"
        }
    }

    /// What CapsAwake uses it for, shown whether or not anything is wrong.
    var purposeKey: LocalizedStringKey {
        switch kind {
        case .backgroundDaemon: "access_daemon_purpose"
        case .accessibility: "access_accessibility_purpose"
        }
    }

    var statusKey: LocalizedStringKey {
        switch status {
        case .granted: "access_status_granted"
        case .notNeeded: "access_status_not_needed"
        case .awaitingApproval: "access_status_awaiting"
        case .failing: "access_status_failing"
        }
    }

    /// What stops working while it is missing. `nil` when nothing is wrong, so a
    /// healthy permission is never dressed up as a problem.
    var impactKey: LocalizedStringKey? {
        switch (kind, status) {
        case (.backgroundDaemon, .awaitingApproval): "access_daemon_impact_awaiting"
        case (.backgroundDaemon, .failing): "access_daemon_impact_failing"
        case (.accessibility, .awaitingApproval), (.accessibility, .failing):
            "access_accessibility_impact"
        case (.accessibility, .notNeeded): "access_accessibility_not_needed_note"
        default: nil
        }
    }

    /// The one-line version the menu shows above the switch.
    var headlineKey: LocalizedStringKey {
        switch (kind, status) {
        case (.backgroundDaemon, .failing): "status_privileged_error"
        case (.backgroundDaemon, _): "status_daemon_approval_required"
        case (.accessibility, _): "status_accessibility_required"
        }
    }

    var actionKey: LocalizedStringKey {
        switch (kind, status) {
        case (.backgroundDaemon, .failing): "restart"
        case (.backgroundDaemon, _): "open_login_items_settings"
        case (.accessibility, _): "open_accessibility_settings"
        }
    }

    var symbolName: String {
        switch status {
        case .granted: "checkmark.circle.fill"
        case .notNeeded: "minus.circle"
        case .awaitingApproval: "exclamationmark.triangle.fill"
        case .failing: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch status {
        case .granted: .green
        case .notNeeded: .secondary
        case .awaitingApproval: .orange
        case .failing: .red
        }
    }
}

/// The status symbol plus its wording, used by Settings and by onboarding.
struct AccessStatusBadge: View {
    let item: SystemAccessItem

    var body: some View {
        Label {
            Text(item.statusKey)
        } icon: {
            Image(systemName: item.symbolName)
                .foregroundStyle(item.tint)
        }
        .font(.callout)
        .foregroundStyle(item.status == .granted ? Color.primary : .secondary)
        .accessibilityElement(children: .combine)
    }
}

/// One permission, spelled out: what it is, whether it is allowed, what CapsAwake
/// needs it for, and what breaks while it is missing.
///
/// The way to System Settings is offered whatever the status. A permission that has
/// been granted can still be taken back or looked at, and hiding the way there while
/// everything worked meant the only route was to break something first.
struct SystemAccessRow: View {
    let item: SystemAccessItem
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.titleKey)
                Spacer()
                AccessStatusBadge(item: item)
                // A push button while something is wrong, because it is the thing to
                // do next; a link while nothing is, because it is only a way through.
                if item.needsAttention {
                    actionButton
                } else {
                    actionButton.buttonStyle(.link)
                }
            }
            Text(item.purposeKey)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let impactKey = item.impactKey {
                Text(impactKey)
                    .font(.callout)
                    .foregroundStyle(item.needsAttention ? item.tint : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var actionButton: some View {
        Button {
            model.resolve(item)
        } label: {
            Text(item.actionKey)
        }
    }
}
