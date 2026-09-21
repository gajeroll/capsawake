import AppKit
import CapsAwakeUI
import SwiftUI

/// Opens the Settings window and puts it in front of whatever the user was working in.
///
/// More work than it sounds, for two reasons. SwiftUI publishes the action that opens
/// a `Settings` scene only through a view's environment, so something has to be hosting
/// a view to hold on to it. And macOS denies activation to an `.accessory` app, so
/// asking for the window and activating leaves it sitting behind the frontmost app,
/// unfocused — CapsAwake is a regular app for exactly as long as Settings is open, and
/// the Dock icon that comes with that goes away again on close.
@MainActor
final class SettingsWindowPresenter {
    /// Called when the Settings window closes, so the caller can drop anything that
    /// only made sense while it was open.
    var onClose: (() -> Void)?

    private var openSettingsAction: (() -> Void)?
    private var hostWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// SwiftUI does not hand out a reference to the `Settings` scene's window, so it is
    /// found by the identifier SwiftUI gives it.
    private static let settingsWindowIdentifierPrefix = "com_apple_SwiftUI_Settings"

    /// How long to wait for the window to exist after asking for it. It does not exist
    /// yet when the action returns.
    private static let appearanceAttempts = 20
    private static let appearancePollInterval: Duration = .milliseconds(25)

    /// Keeps a hosted `SettingsOpener` alive so its environment action stays available.
    func install() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.stationary, .ignoresCycle]
        // Keep it out of the accessibility tree: assistive tools and UI automation
        // should not see a stray one-pixel window.
        window.setAccessibilityElement(false)
        window.contentView = NSHostingView(
            rootView: SettingsOpener { [weak self] action in
                self?.openSettingsAction = action
            }
        )
        // Never ordered in: an on-screen window, even a transparent one pixel wide,
        // keeps the window server telling it about occlusion and tracking areas
        // forever. That cost 2-3% of a core and drowned the log, and the redraws it
        // delayed were the menu bar icon's.
        hostWindow = window
    }

    func open() {
        guard let openSettingsAction else {
            Log.error("Could not open the Settings window")
            return
        }
        NSApp.setActivationPolicy(.regular)
        openSettingsAction()
        Task {
            for _ in 0..<Self.appearanceAttempts {
                if let window = Self.settingsWindow {
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    // macOS grants activation only to the app that owns the user's
                    // last event, and while inactive an ordinary order-front is
                    // ignored, so ask for the front unconditionally too.
                    window.orderFrontRegardless()
                    becomeAccessoryWhenClosed(window)
                    return
                }
                try? await Task.sleep(for: Self.appearancePollInterval)
            }
            Log.error("Settings window did not appear")
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func stop() {
        removeCloseObserver()
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue.hasPrefix(settingsWindowIdentifierPrefix) == true
        }
    }

    private func becomeAccessoryWhenClosed(_ window: NSWindow) {
        removeCloseObserver()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = NSApp.setActivationPolicy(.accessory)
                self?.onClose?()
            }
        }
    }

    private func removeCloseObserver() {
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
    }
}
