import Testing

@testable import CapsAwakeCore

@Test func aCombinationIsDrawnInTheOrderMacOSUses() {
    let modifiers: CapsLockModifiers = [.shift, .control]
    #expect(modifiers.symbols == "⌃⇧")
    #expect(modifiers.shortcutSymbols == "⌃⇧⇪")
}

@Test func eachModifierHasItsOwnGlyph() {
    #expect(CapsLockModifiers.control.symbols == "⌃")
    #expect(CapsLockModifiers.option.symbols == "⌥")
    #expect(CapsLockModifiers.shift.symbols == "⇧")
    #expect(CapsLockModifiers.command.symbols == "⌘")
}

/// No modifiers is a real choice — it means no key switches capitals — so it has to
/// come out as the key on its own rather than as something malformed.
@Test func noModifiersLeaveJustTheKey() {
    let none: CapsLockModifiers = []
    #expect(none.symbols.isEmpty)
    #expect(none.shortcutSymbols == "⇪")
}
