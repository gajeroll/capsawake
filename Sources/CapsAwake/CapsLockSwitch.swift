import AppKit
import CapsAwakeCore
import CapsAwakeSystem
import Carbon.HIToolbox
import Foundation

/// The Caps Lock key, as the switch the user operates.
///
/// The LED is the switch: CapsAwake reads the hardware lock directly, which is the only
/// path that works with no Accessibility permission, because both the event tap and the
/// `NSEvent` monitors need it. So there are three ways a press arrives — the tap, the
/// monitors, the poll — and this is the one place that has to tell a press of the key
/// from an echo of a write CapsAwake made itself.
///
/// That is what the two windows below are for, and having them in one type is most of
/// the reason this exists: they used to be set in nine places across the app delegate,
/// and reading them meant reading all of it.
@MainActor
final class CapsLockSwitch {
    /// A press of Caps Lock on its own, with the lock state it left behind. The user
    /// reaching for the switch.
    var onSwitchPressed: ((Bool) -> Void)?
    /// A polled reading that is not a press, so state can follow the hardware without
    /// treating it as intent.
    var onLockObserved: ((Bool?) -> Void)?
    /// The key was pressed but the hardware never moved, so there is nothing to read
    /// the user's intent off except the press itself.
    var onPressWithoutMovement: (() -> Void)?
    /// The keys held with a press, while Settings is waiting to be told which ones
    /// should switch capitals.
    var onCombinationRecorded: ((CapsLockModifiers) -> Void)?
    /// The keyboard input source changed, which clears the lock as a side effect.
    var onInputSourceChanged: (() -> Void)?

    /// Whether the tap is running, which decides who is doing the listening.
    var isFilterActive: () -> Bool = { false }
    /// Where the reducer currently wants the lock, so a recorded press can be put back.
    var desiredLock: () -> Bool = { false }
    /// Where the state machine last recorded the lock. Read rather than kept, so this
    /// type cannot drift from the state it is reporting to.
    var knownLock: () -> Bool? = { nil }
    /// Whether Settings is waiting for the combination.
    var isRecording = false

    private let capsLock: CapsLockController
    private let filter: CapsLockEventFilter

    private var pollTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var inputSourceObserver: NSObjectProtocol?

    /// The LED doubles as the user's switch, so poll it.
    private let pollInterval: TimeInterval = 1

    /// CapsAwake writes the LED itself, and switching input sources clears it. Changes
    /// seen inside this window are recorded but not read as a key press.
    private var ignoreLEDChangesUntil = Date.distantPast
    /// The same echo, seen by the event monitors rather than the poll, after a press
    /// that was recorded instead of acted on.
    private var ignoreMonitoredKeyUntil = Date.distantPast
    private let echoWindow: TimeInterval = 1

    /// How long to watch the hardware for movement after a press the monitors reported.
    private let movementAttempts = 20
    private let movementPollInterval: Duration = .milliseconds(15)

    private let inputSourceNotification = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )

    init(capsLock: CapsLockController, filter: CapsLockEventFilter) {
        self.capsLock = capsLock
        self.filter = filter
    }

    func start() {
        installMonitors()
        installInputSourceObserver()
        pollTimer = repeatingTimer(every: pollInterval, tolerance: pollInterval / 2) {
            [weak self] in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
            self.inputSourceObserver = nil
        }
    }

    /// Reads the lock once, for the caller that wants to flip it from where it is —
    /// the switch in the menu, or in Settings.
    func currentLock() async -> Bool? {
        await capsLock.currentState()
    }

    /// Declares a write before it lands. The key release reports the lock afterwards,
    /// and the poll may catch it in between; neither is the user reaching for the
    /// switch.
    func write(lock on: Bool) {
        filter.noteLock(on)
        ignoreLEDChangesUntil = Date().addingTimeInterval(echoWindow)
        Task { await applyLock(on) }
    }

    /// The press that was recorded belonged to neither switch, but it still flipped the
    /// hardware lock on its way in, so the lock goes back where sleep prevention wants
    /// it — and the echo of that write is ignored on both paths.
    func putLockBack() {
        ignoreMonitoredKeyUntil = Date().addingTimeInterval(echoWindow)
        write(lock: desiredLock())
    }

    /// Shift+Caps Lock asks for capitals, not for sleep prevention, but the press still
    /// flips the hardware lock on its way in. The reducer writes it back immediately;
    /// this only keeps the poll from reading that flip as the user reaching for the
    /// switch.
    func expectLockEcho() {
        ignoreLEDChangesUntil = Date().addingTimeInterval(echoWindow)
    }

    /// Writes the lock off on the way out, with no echo bookkeeping: by the time
    /// quitting gets here the monitors and the poll have been stopped and the tap
    /// torn down, so there is nobody left to mistake the write for a press.
    func clearLock() async {
        _ = await capsLock.setState(false)
    }

    /// Adopts the LED as it stands at launch. A lit one means the switch is on.
    func adoptLockAtLaunch() async -> Bool? {
        await capsLock.currentState()
    }

    // MARK: - Where presses come from

    private func installMonitors() {
        let keyCode = UInt16(kVK_CapsLock)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard event.keyCode == keyCode else { return }
            let held = CapsLockModifiers(event.modifierFlags)
            Task { @MainActor in self?.handleMonitoredKey(held: held) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            if event.keyCode == keyCode {
                let held = CapsLockModifiers(event.modifierFlags)
                Task { @MainActor in self?.handleMonitoredKey(held: held) }
            }
            return event
        }
    }

    private func installInputSourceObserver() {
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: inputSourceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Switching input sources clears the Caps Lock LED. That must not be
                // read as the user turning CapsAwake off.
                self.expectLockEcho()
                self.onInputSourceChanged?()
            }
        }
    }

    /// The monitors exist for when the event tap is not running. While it is, the only
    /// Caps Lock events that reach them are the capitals combination it passes through,
    /// and those belong to the other switch.
    private func handleMonitoredKey(held: CapsLockModifiers) {
        // Putting the lock back after a recorded press reports the modifiers a second
        // time, and with no tap to tell that from a press it would read as one.
        guard Date() >= ignoreMonitoredKeyUntil else { return }
        if isRecording {
            onCombinationRecorded?(held)
            return
        }
        let capitals = UserPreferences.capitalsModifiers
        guard !(isFilterActive() && !capitals.isEmpty && held == capitals) else { return }
        watchForMovement()
    }

    /// The fallback for when the tap is not running and all we know is that the key was
    /// pressed: the event monitors report no lock state we can trust, so wait for the
    /// hardware to move rather than sampling once at a fixed delay.
    ///
    /// If the state never moves, the press still counts.
    private func watchForMovement() {
        Task {
            let previous = knownLock()
            for _ in 0..<movementAttempts {
                try? await Task.sleep(for: movementPollInterval)
                guard let led = await capsLock.currentState(), led != previous else { continue }
                onSwitchPressed?(led)
                return
            }
            Log.debug("Caps Lock key: hardware state unchanged, treating as a toggle")
            onPressWithoutMovement?()
        }
    }

    private func poll() {
        Task {
            guard let led = await capsLock.currentState(), led != knownLock() else { return }
            guard Date() >= ignoreLEDChangesUntil else {
                onLockObserved?(led)
                return
            }
            Log.debug("Caps Lock LED changed to \(led)")
            onSwitchPressed?(led)
        }
    }

    private func applyLock(_ on: Bool) async {
        if await capsLock.setState(on) {
            onLockObserved?(on)
        } else {
            Log.error("Could not set Caps Lock LED to \(on)")
        }
    }
}
