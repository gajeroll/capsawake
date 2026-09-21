import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The small letter Caps Lock types while Shift is held, read from the keyboard layout
/// in force.
///
/// Capitals here are the Caps Lock modifier added to key events, and a layout reads
/// that modifier one way only: asked for Shift alongside it, it answers with the
/// capital. So the character has to be put on the event itself. A key event carries the
/// text it types as well as the keys that were down, which is how the hardware lock
/// does it — Caps Lock and Shift both held, and `a` typed — and an event saying the
/// same thing is taken the same way, IMEs and Shift shortcuts included.
///
/// Only the keys where Shift was capitalizing have a small letter to type. On `2` Shift
/// reaches `@`, which has no other case, and those keys are left alone. The layout
/// answers in its own terms: Shift is the key's case switch where what Shift types is
/// what Caps Lock types. Comparing the two characters as text instead would be wrong on
/// the layouts that need this most — Turkish types `i` and `İ` on one key, and `i`
/// uppercases to `I` in every locale but that one.
@MainActor
public final class CasedKeys {
    private struct Question: Hashable {
        let keyCode: UInt16
        /// Layouts answer per keyboard, and plugging one in changes no input source.
        let keyboardType: UInt32
        let option: Bool
    }

    /// A layout to answer from whatever the Mac is set to, for tests that have to pin
    /// one. Nothing else passes it: the app follows the input source.
    private let pinnedLayout: Data?

    /// The layout, and the answers read out of it. Both are dropped when the input
    /// source changes, because the next layout answers for itself.
    private var layout: Data?
    private var answers: [Question: String?] = [:]
    private var inputSourceObserver: NSObjectProtocol?

    private static let inputSourceNotification = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )

    public init(layout: Data? = nil) {
        pinnedLayout = layout
    }

    /// Starts following the input source, since a different layout gives different
    /// answers.
    public func start() {
        guard inputSourceObserver == nil else { return }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.inputSourceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forgetLayout()
            }
        }
    }

    public func stop() {
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
            self.inputSourceObserver = nil
        }
        forgetLayout()
    }

    /// What this key types under Caps Lock with Shift held: the small letter, or
    /// nothing where Shift is reaching a character of its own and there is nothing to
    /// put right.
    ///
    /// A key the layout cannot answer for types nothing here, which leaves the event as
    /// the keyboard sent it.
    public func smallLetter(
        keyCode: Int64,
        keyboardType: Int64,
        flags: CGEventFlags
    ) -> String? {
        guard let keyCode = UInt16(exactly: keyCode) else { return nil }
        let question = Question(
            keyCode: keyCode,
            // A synthetic event may name no keyboard; the one attached to the Mac
            // answers for it.
            keyboardType: UInt32(exactly: keyboardType).flatMap { $0 == 0 ? nil : $0 }
                ?? UInt32(LMGetKbdType()),
            option: flags.contains(.maskAlternate)
        )
        if let answer = answers[question] { return answer }
        let answer = ask(question)
        answers[question] = answer
        return answer
    }

    private func ask(_ question: Question) -> String? {
        let option = question.option ? UInt32(optionKey >> 8) : 0
        guard
            let plain = character(question, modifiers: option),
            let shifted = character(question, modifiers: option | UInt32(shiftKey >> 8)),
            let capitalized = character(question, modifiers: option | UInt32(alphaLock >> 8)),
            plain != shifted, capitalized == shifted
        else {
            return nil
        }
        return plain
    }

    /// What the key types, as the layout has it. Dead keys are translated as the
    /// character they stand for rather than entered, so asking cannot leave a dead key
    /// half-pressed.
    private func character(_ question: Question, modifiers: UInt32) -> String? {
        guard let data = currentLayout() else { return nil }
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0
        var deadKeyState: UInt32 = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                question.keyCode,
                UInt16(kUCKeyActionDown),
                modifiers,
                question.keyboardType,
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    private func currentLayout() -> Data? {
        if let pinnedLayout { return pinnedLayout }
        if let layout { return layout }
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return layout
    }

    private func forgetLayout() {
        layout = nil
        answers.removeAll()
    }
}
