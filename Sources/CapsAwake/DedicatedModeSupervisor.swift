import AppKit
import CapsAwakeCore
import CapsAwakeSystem
import Foundation

/// Keeps the Caps Lock event tap in line with the Dedicated Mode preference, and waits
/// for the Accessibility permission it needs.
///
/// macOS grants Accessibility out of band, so a missing permission is not terminal: the
/// tap is retried until it starts, rather than making the user relaunch after allowing
/// it in System Settings.
@MainActor
final class DedicatedModeSupervisor {
    /// Whether the tap is running, and whether it is meant to be. Reported only when it
    /// changes, so polling does not flood the state machine.
    var onStatusChanged: ((_ ready: Bool, _ enabled: Bool) -> Void)?

    private let filter: CapsLockEventFilter
    private var supervisor: Task<Void, Never>?
    private var didPrompt = false
    private var lastStatus: Status?

    /// Retry cadence while the permission is still missing. Once the tap is up, the
    /// slower reconcile tick is enough to notice a revocation.
    private let retryInterval: Duration = .seconds(1)

    private struct Status: Equatable {
        let ready: Bool
        let enabled: Bool
    }

    init(filter: CapsLockEventFilter) {
        self.filter = filter
    }

    /// Brings the tap in line with the preference. `prompt` asks macOS for the
    /// permission, which it will only show the user once per launch.
    func refresh(prompt: Bool) {
        guard UserPreferences.dedicatedMode else {
            filter.stop()
            publish(ready: true, enabled: false)
            return
        }

        if prompt, !didPrompt, !AccessibilityPermission.isTrusted {
            didPrompt = true
            AccessibilityPermission.prompt()
        }

        let ready = filter.start(promptForPermission: false)
        publish(ready: ready, enabled: true)
        if !ready { startWaitingForPermission() }
    }

    /// Whether Dedicated Mode is satisfied as things stand. Called from the reconcile
    /// tick, and starts the faster retry again if the tap has gone away.
    @discardableResult
    func poll() -> Bool {
        if satisfied() { return true }
        startWaitingForPermission()
        return false
    }

    func stop() {
        supervisor?.cancel()
        supervisor = nil
    }

    private func satisfied() -> Bool {
        guard UserPreferences.dedicatedMode else { return true }
        if filter.isActive { return true }

        let ready = filter.start(promptForPermission: false)
        if ready {
            Log.info("Caps Lock event tap started after Accessibility was granted")
        }
        publish(ready: ready, enabled: true)
        return ready
    }

    private func startWaitingForPermission() {
        guard supervisor == nil else { return }
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.satisfied() {
                    self.supervisor = nil
                    return
                }
                try? await Task.sleep(for: self.retryInterval)
            }
        }
    }

    private func publish(ready: Bool, enabled: Bool) {
        let next = Status(ready: ready, enabled: enabled)
        guard lastStatus != next else { return }
        lastStatus = next
        onStatusChanged?(ready, enabled)
    }
}

/// The panes of System Settings CapsAwake sends people to.
enum SystemSettingsLink {
    static func openAccessibility() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
