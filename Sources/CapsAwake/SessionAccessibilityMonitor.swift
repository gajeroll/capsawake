import AppKit
import CapsAwakeCore
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Whether the user's session is somewhere the event filter can do its work.
///
/// Everything here is reported rather than acted on: an observation becomes a
/// `SessionAccessibility` snapshot, and what to do about it is the reducer's
/// decision. The screen locking and the console changing hands are announced by
/// macOS; secure input is not announced by anything, so it is polled — a cheap
/// flag, read once a second so a password field is noticed about as fast as it is
/// clicked into.
@MainActor
final class SessionAccessibilityMonitor {
    /// Fired only when something moved, with the whole snapshot.
    var onChange: ((SessionAccessibility) -> Void)?

    private(set) var current = SessionAccessibility()

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var secureInputTimer: Timer?

    private let secureInputPollInterval: TimeInterval = 1

    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    func start() {
        guard distributedObservers.isEmpty else { return }
        distributedObservers = [
            observeDistributed(Self.screenLockedNotification) { $0.screenLocked = true },
            observeDistributed(Self.screenUnlockedNotification) { $0.screenLocked = false },
        ]
        workspaceObservers = [
            observeWorkspace(NSWorkspace.sessionDidResignActiveNotification) {
                $0.sessionActive = false
            },
            observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) {
                $0.sessionActive = true
            },
        ]
        secureInputTimer = repeatingTimer(
            every: secureInputPollInterval,
            tolerance: secureInputPollInterval / 2
        ) { [weak self] in
            self?.readSecureInput()
        }
        // Where things already stand, so launching into a locked or handed-over
        // session is not read as an accessible one.
        poll()
        readSecureInput()
    }

    func stop() {
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers = []
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        secureInputTimer?.invalidate()
        secureInputTimer = nil
    }

    /// Safety net only: the notifications own the live path. Re-reads what can be
    /// read, so a missed notification is put right within a reconcile tick.
    func poll() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return }
        update {
            if let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool {
                $0.sessionActive = onConsole
            }
            // Not a documented key, so its absence says nothing: the notifications
            // still decide, and this only corrects a reading they already made.
            if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
                $0.screenLocked = locked
            }
        }
    }

    private func readSecureInput() {
        update { $0.secureInputActive = IsSecureEventInputEnabled() }
    }

    private func update(_ change: (inout SessionAccessibility) -> Void) {
        var snapshot = current
        change(&snapshot)
        guard snapshot != current else { return }
        current = snapshot
        Log.debug(
            """
            session accessibility: locked=\(snapshot.screenLocked) \
            active=\(snapshot.sessionActive) secureInput=\(snapshot.secureInputActive)
            """
        )
        onChange?(snapshot)
    }

    private func observeDistributed(
        _ name: Notification.Name,
        change: @escaping @MainActor (inout SessionAccessibility) -> Void
    ) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(change) }
        }
    }

    private func observeWorkspace(
        _ name: Notification.Name,
        change: @escaping @MainActor (inout SessionAccessibility) -> Void
    ) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(change) }
        }
    }
}
