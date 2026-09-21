import Foundation

/// Something CapsAwake needs from macOS before part of it can work.
///
/// The warning icon, the menu and the Settings window all render this one list, so
/// the icon cannot turn into a warning without a row somewhere saying why.
public enum SystemAccessKind: String, Sendable, Equatable, CaseIterable, Identifiable {
    /// The root daemon that owns the sleep setting, approved in Login Items.
    case backgroundDaemon
    /// The Accessibility grant the Caps Lock event tap needs.
    case accessibility

    public var id: String { rawValue }
}

public enum SystemAccessStatus: Sendable, Equatable {
    case granted
    /// The current settings do not call for it.
    case notNeeded
    /// Waiting for the user to allow it in System Settings.
    case awaitingApproval
    /// Allowed, or never refused, but what it enables is not working.
    case failing
}

public struct SystemAccessItem: Sendable, Equatable, Identifiable {
    public let kind: SystemAccessKind
    public let status: SystemAccessStatus

    public init(kind: SystemAccessKind, status: SystemAccessStatus) {
        self.kind = kind
        self.status = status
    }

    public var id: SystemAccessKind { kind }

    /// Whether this is something the user has to act on.
    public var needsAttention: Bool {
        switch status {
        case .awaitingApproval, .failing: true
        case .granted, .notNeeded: false
        }
    }

    /// How the status icon renders this item when it is the one being shown.
    public var errorReason: ErrorReason? {
        guard needsAttention else { return nil }
        switch kind {
        case .backgroundDaemon:
            return status == .awaitingApproval ? .daemonApproval : .privileged
        case .accessibility:
            return .dedicatedPermission
        }
    }
}
