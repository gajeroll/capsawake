import ApplicationServices
import CapsAwakeCore
import CoreGraphics
import Foundation
import os

/// What a Caps Lock press means, decided from the event and the chosen combination.
public enum CapsLockKeyAction: Equatable, Sendable {
    /// The switch CapsAwake took the key over for.
    case toggleCapsAwake
    /// The combination the user set aside for capitals: the plain Caps Lock the key
    /// would otherwise be.
    case toggleCapsLockTyping
    /// Settings is waiting to be told which keys should switch capitals, so this
    /// press only says which ones were held with it.
    case recordCombination(CapsLockModifiers)
    case notCapsLock
}

public enum CapsLockFilterPolicy {
    public static let capsLockKeyCode: Int64 = 57

    public static func sanitizedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var sanitized = flags
        sanitized.remove(.maskAlphaShift)
        return sanitized
    }

    /// Adds the Caps Lock modifier the hardware is not holding.
    ///
    /// Capitals come from the flag on the key event, so they can be produced
    /// without the keyboard's lock bit — which is what keeps the LED free to mean
    /// only one thing.
    ///
    /// The flag alone cannot say everything the lock says. Caps Lock is a case switch
    /// rather than a Shift that sticks, so holding Shift under it types the small
    /// letter, and a layout given both answers with the capital. That is put right by
    /// writing the letter onto the event rather than by taking Shift off it: the event
    /// then says what the hardware lock's event says, Shift and all.
    public static func capitalizedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var capitalized = flags
        capitalized.insert(.maskAlphaShift)
        return capitalized
    }

    /// Whether Shift on this event might be doing nothing but capitalizing, and so is
    /// worth asking the layout about.
    ///
    /// Only a key being typed is asked about: a modifier going down or up carries no
    /// character of its own. Nor is a shortcut, which is spelled with the Shift it
    /// holds — ⌘⇧S is not ⌘S, and its letter is nobody's to rewrite.
    public static func shiftMayBeCapitalizing(
        eventType: CGEventType,
        flags: CGEventFlags
    ) -> Bool {
        guard eventType == .keyDown, flags.contains(.maskShift) else { return false }
        return !flags.contains(.maskCommand) && !flags.contains(.maskControl)
    }

    /// The combination has to match exactly. Holding more than it asks for is not the
    /// shortcut, so it goes to the switch the key is otherwise for, and there is no
    /// combination that quietly does two things.
    public static func action(
        eventType: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        capitalsModifiers: CapsLockModifiers,
        isRecording: Bool = false
    ) -> CapsLockKeyAction {
        guard eventType == .flagsChanged, keyCode == capsLockKeyCode else { return .notCapsLock }
        // Recording outranks both switches: the press is being asked about, not made.
        if isRecording { return .recordCombination(heldModifiers(flags)) }
        guard !capitalsModifiers.isEmpty else { return .toggleCapsAwake }
        return heldModifiers(flags) == capitalsModifiers ? .toggleCapsLockTyping : .toggleCapsAwake
    }

    /// The modifiers held alongside Caps Lock.
    public static func heldModifiers(_ flags: CGEventFlags) -> CapsLockModifiers {
        var held: CapsLockModifiers = []
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }
}

/// Where the Caps Lock modifier stands, as far as the events and the app's own writes
/// have said so.
///
/// One press of the key can produce two events. Releasing it reports the modifiers
/// again, and by then the app has usually put the lock back where sleep prevention
/// wants it, so the flags differ from the press and the event is delivered rather
/// than folded away. Nothing distinguishes it from a press by source, keyboard, or
/// modifiers, and it can arrive a third of a second later, so taking it as a press
/// toggles a switch nobody touched — which is what read as the key chattering.
///
/// What does distinguish them is the lock itself. A press always flips it, so a press
/// reports a lock we do not already know about; a release reports the one we do.
/// Nothing here is timed, so holding the key as long as you like is still one press.
public struct CapsLockPressReader {
    private var knownLock: Bool?

    public init(lockOn: Bool? = nil) {
        knownLock = lockOn
    }

    /// Whether an event reporting `lockOn` is a press of the key.
    public mutating func isPress(lockOn: Bool) -> Bool {
        guard knownLock != lockOn else { return false }
        knownLock = lockOn
        return true
    }

    /// Records where the lock stands without it being a press: the app writing it, or
    /// reading the hardware back.
    public mutating func note(lockOn: Bool) {
        knownLock = lockOn
    }
}

/// Suppresses the Caps Lock modifier so the key can act as a toggle without
/// switching the keyboard into all-caps typing.
///
/// The tap is installed on the main run loop and its callback fires on the main
/// thread, so the whole type is main-actor isolated and needs no locking.
@MainActor
public final class CapsLockEventFilter {
    /// Reports a press of Caps Lock on its own, with the lock state it left behind.
    public var onUserCapsLockKeyPress: ((Bool) -> Void)?
    public var onCapsLockTypingChanged: ((Bool) -> Void)?
    /// Reports the keys held with a press while `isRecording`, so the combination can
    /// be set by pressing it.
    public var onCombinationRecorded: ((CapsLockModifiers) -> Void)?

    /// While set, a press switches nothing and is reported for recording instead.
    public var isRecording = false

    /// Whether the user asked, with the capitals combination, for capitals to work
    /// again.
    ///
    /// This lives here because the tap callback has to decide whether to strip the
    /// modifier synchronously, before the event goes any further.
    public private(set) var capsLockTypingRequested = false

    /// The modifiers that switch capitals rather than CapsAwake. The tap reads this
    /// on every event, so changing it takes effect on the next press.
    public var capitalsModifiers: CapsLockModifiers = .shift

    /// Whether Shift under capitals asks for the small letter, the way Windows' Caps
    /// Lock reads it. The Mac's own answers Shift with the capital, so this is off
    /// until the user chooses the other habit in Settings.
    public var shiftTypesSmallLetters = false

    private static let log = Logger(subsystem: AppIdentity.osLogSubsystem, category: "input")

    private var pressReader = CapsLockPressReader()
    /// Asked, while capitals are locked on, which keys Shift is only capitalizing.
    private let casedKeys = CasedKeys()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Whether the tap exists and macOS still has it enabled.
    public var isActive: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    public init() {}

    /// Installs and enables the tap. Returns false when macOS denies it, which
    /// normally means Accessibility permission has not been granted yet.
    @discardableResult
    public func start(promptForPermission: Bool) -> Bool {
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return true
        }

        let trusted =
            promptForPermission
            ? AccessibilityPermission.prompt()
            : AccessibilityPermission.isTrusted
        guard trusted else { return false }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        )
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let filter = Unmanaged<CapsLockEventFilter>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    // The callback runs on the main run loop. Only the decision
                    // crosses the isolation boundary, because `CGEvent` and
                    // `Unmanaged` are not Sendable.
                    let suppress = MainActor.assumeIsolated {
                        filter.handle(type: type, event: event)
                    }
                    return suppress ? nil : Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        casedKeys.start()
        return isActive
    }

    public func stop() {
        // Nothing will be watching the lock, so what it says now tells us nothing
        // about the next press we see.
        pressReader = CapsLockPressReader()
        clearCapsLockTyping()
        casedKeys.stop()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Rewrites the Caps Lock modifier on `event` and reports whether the event
    /// should be swallowed instead of forwarded.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let action = CapsLockFilterPolicy.action(
            eventType: type,
            keyCode: keyCode,
            flags: flags,
            capitalsModifiers: capitalsModifiers,
            isRecording: isRecording
        )

        guard action != .notCapsLock else {
            // Capitals are decided here rather than by the hardware lock, which is
            // left to mean sleep prevention and nothing else.
            event.flags =
                capsLockTypingRequested
                ? CapsLockFilterPolicy.capitalizedFlags(flags)
                : CapsLockFilterPolicy.sanitizedFlags(flags)
            if capsLockTypingRequested && shiftTypesSmallLetters {
                typeSmallLetterUnderShift(type: type, event: event, flags: flags)
            }
            return false
        }

        // The key never reaches other apps, whichever switch it was aimed at.
        let lockOn = flags.contains(.maskAlphaShift)
        let isPress = pressReader.isPress(lockOn: lockOn)
        Self.log.debug(
            """
            Caps Lock event: action=\(String(describing: action), privacy: .public) \
            lock=\(lockOn, privacy: .public) \
            \(isPress ? "taken as a press" : "the lock is where we left it; not a press", privacy: .public)
            """
        )
        guard isPress else { return true }

        switch action {
        case .toggleCapsAwake:
            onUserCapsLockKeyPress?(lockOn)
        case .toggleCapsLockTyping:
            capsLockTypingRequested.toggle()
            onCapsLockTypingChanged?(capsLockTypingRequested)
        case .recordCombination(let held):
            onCombinationRecorded?(held)
        case .notCapsLock:
            break
        }
        return true
    }

    /// Types the small letter on the keys where Shift, under capitals, is only asking
    /// for the capital of what the key types anyway.
    ///
    /// A key event carries the text it types as well as the keys that were down, and
    /// the two are what the hardware lock puts together: Caps Lock and Shift both held,
    /// and the small letter typed. Writing the letter is what says that; the modifiers
    /// are left as they arrived, so an IME still reads Shift as the ask for direct
    /// English input, and a Shift shortcut is still a Shift shortcut.
    ///
    /// The layout is asked only once the event is one where the question arises, so
    /// most keystrokes never reach it at all.
    private func typeSmallLetterUnderShift(
        type: CGEventType,
        event: CGEvent,
        flags: CGEventFlags
    ) {
        guard CapsLockFilterPolicy.shiftMayBeCapitalizing(eventType: type, flags: flags),
            let letter = casedKeys.smallLetter(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType),
                flags: flags
            )
        else {
            return
        }
        var units = Array(letter.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
    }

    /// Tells the filter where the lock stands when the app moves it or reads it back,
    /// so the release that follows is not read as a press of its own.
    public func noteLock(_ lockOn: Bool) {
        pressReader.note(lockOn: lockOn)
    }

    /// Sets the request from somewhere other than the keyboard, so the switch in the
    /// menu and in Settings can make and take back the same request the combination
    /// does.
    public func setCapsLockTyping(_ requested: Bool) {
        guard capsLockTypingRequested != requested else { return }
        capsLockTypingRequested = requested
        onCapsLockTypingChanged?(requested)
    }

    /// Called when the tap goes away, since nothing is being stripped any more and
    /// the key is a plain Caps Lock again.
    private func clearCapsLockTyping() {
        setCapsLockTyping(false)
    }
}
