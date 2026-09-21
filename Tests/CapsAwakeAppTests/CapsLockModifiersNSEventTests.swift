import AppKit
import CapsAwakeCore
import CapsAwakeSystem
import CoreGraphics
import Testing

@testable import CapsAwake

/// The event tap reads `CGEventFlags` and the `NSEvent` monitors read
/// `NSEvent.ModifierFlags`, so the modifiers held with Caps Lock are mapped twice, from
/// two different Apple types. The bodies cannot be collapsed into one, but they can be
/// held to the same table — which is what this is. Either one drifting would mean the
/// combination the user recorded through one path is not the one the other recognises.

private struct Case {
    let name: String
    let event: NSEvent.ModifierFlags
    let tap: CGEventFlags
    let expected: CapsLockModifiers
}

private let table: [Case] = [
    Case(name: "nothing held", event: [], tap: [.maskAlphaShift], expected: []),
    Case(name: "shift", event: [.shift], tap: [.maskAlphaShift, .maskShift], expected: [.shift]),
    Case(
        name: "control",
        event: [.control],
        tap: [.maskAlphaShift, .maskControl],
        expected: [.control]
    ),
    Case(
        name: "option",
        event: [.option],
        tap: [.maskAlphaShift, .maskAlternate],
        expected: [.option]
    ),
    Case(
        name: "command",
        event: [.command],
        tap: [.maskAlphaShift, .maskCommand],
        expected: [.command]
    ),
    Case(
        name: "all four",
        event: [.control, .option, .shift, .command],
        tap: [.maskAlphaShift, .maskControl, .maskAlternate, .maskShift, .maskCommand],
        expected: [.control, .option, .shift, .command]
    ),
]

@Test func bothPathsReadTheSameModifiersOffAPress() {
    for entry in table {
        #expect(
            CapsLockModifiers(entry.event) == entry.expected,
            "NSEvent path, \(entry.name)"
        )
        #expect(
            CapsLockFilterPolicy.heldModifiers(entry.tap) == entry.expected,
            "event tap path, \(entry.name)"
        )
    }
}

/// Caps Lock is the key being pressed, not a modifier held with it. `NSEvent` does not
/// report it in `modifierFlags` the way the tap reports `.maskAlphaShift`, but the two
/// must agree that it is not part of the combination either way.
@Test func theLockItselfIsNotOneOfTheModifiers() {
    #expect(CapsLockModifiers(.capsLock) == [])
    #expect(CapsLockFilterPolicy.heldModifiers([.maskAlphaShift]) == [])
}
