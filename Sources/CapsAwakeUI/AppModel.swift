import CapsAwakeCore
import SwiftUI

/// Reactive state the menu bar and the Settings window render, plus the actions
/// they can trigger.
///
/// Preferences are intentionally absent: the views read and write them straight
/// through `@AppStorage`, and the app reacts to `UserDefaults.didChangeNotification`.
@MainActor
@Observable
public final class AppModel {
    public var presentation: StatusPresentation = .idle

    /// Every permission CapsAwake depends on and the state it is in. The status
    /// icon, the menu and the Settings window all read this, so what the icon says
    /// and what the menu offers cannot drift apart.
    public var systemAccess: [SystemAccessItem] = []

    /// Advisory note when IOKit still thinks closing the lid would sleep the Mac.
    /// Not escalated to an error icon — the value is known to be unreliable.
    public var lidCloseWarning = false

    /// The Mac's own sleep time for the power source in use, in minutes, with zero
    /// meaning it is set never to sleep. `nil` until it has been read.
    ///
    /// Settings quotes it back, because a setting about reaching the sleep time reads
    /// as broken on a Mac that has none.
    public var sleepAfterMinutes: Int?

    /// Which Energy Modes this Mac offers.
    public let energy = EnergyModeModel()

    /// Whether the keyboard is locked to capitals as things stand. The status icon
    /// draws its fill from the same value, so the switch and the icon cannot say
    /// different things about the same keyboard.
    public var capitalsLocked = false

    /// Whether Settings is waiting for the user to press the keys they want to use
    /// for capitals, rather than asking them to describe the combination.
    public var isRecordingCapitalsShortcut = false

    /// Locks the keyboard to capitals, or stops it — the capitals combination by
    /// another route, and so the same switch rather than a second one.
    public var onSetCapitalsLocked: ((Bool) -> Void)?
    public var onRecordCapitalsShortcut: ((Bool) -> Void)?
    public var onToggleRequested: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenAccessibilitySettings: (() -> Void)?
    public var onOpenLoginItemsSettings: (() -> Void)?
    public var onRestart: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {}

    /// Whether sleep prevention is in effect, which is what the menu's checkmark
    /// and the status icon both show.
    public var isActive: Bool {
        if case .active = presentation { true } else { false }
    }

    /// The permissions the user has to do something about, which is exactly the set
    /// that turns the status icon into a warning.
    public var pendingAccess: [SystemAccessItem] {
        systemAccess.filter(\.needsAttention)
    }

    public func access(_ kind: SystemAccessKind) -> SystemAccessItem? {
        systemAccess.first { $0.kind == kind }
    }

    /// Does whatever this item's button offers to do about it.
    ///
    /// A daemon that is already approved and still failing is the one case that is
    /// not a trip to System Settings: sending the user back to Login Items to
    /// approve something already ticked is a dead end, and a relaunch is what picks
    /// up a replaced or crashed daemon.
    public func resolve(_ item: SystemAccessItem) {
        switch (item.kind, item.status) {
        case (.backgroundDaemon, .failing): onRestart?()
        case (.backgroundDaemon, _): onOpenLoginItemsSettings?()
        case (.accessibility, _): onOpenAccessibilitySettings?()
        }
    }
}
