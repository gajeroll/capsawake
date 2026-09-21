import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import CapsAwakeSystem

/// A layout by name, whether or not the Mac is set to it, so what these tests check is
/// the same on every machine. `true` asks for the layouts that are installed but not
/// enabled, which is what makes Turkish and French available to a US Mac.
private func layout(_ identifier: String) -> Data? {
    let query = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    guard
        let sources = TISCreateInputSourceList(query, true)?.takeRetainedValue()
            as? [TISInputSource],
        let source = sources.first,
        let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
        return nil
    }
    return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
}

private let letterKey = Int64(kVK_ANSI_A)
private let digitKey = Int64(kVK_ANSI_2)
private let arrowKey = Int64(kVK_LeftArrow)
/// The key that types `i` on the Turkish layout, and `İ` with Shift.
private let turkishDottedI: Int64 = 1
/// The keyboard the event came from, which the layout answers per. Zero is the caller
/// having none to name, and stands for the keyboard attached to this Mac.
private let anyKeyboard: Int64 = 0

@MainActor
@Test func aLetterKeyAnswersWithItsSmallLetter() throws {
    let keys = CasedKeys(layout: try #require(layout("com.apple.keylayout.US")))
    #expect(keys.smallLetter(keyCode: letterKey, keyboardType: anyKeyboard, flags: []) == "a")
    // Option reaches a character of its own, and that character has a case too: å and Å.
    #expect(
        keys.smallLetter(keyCode: letterKey, keyboardType: anyKeyboard, flags: [.maskAlternate])
            == "å"
    )
}

/// A digit has no capital, so Shift on the digit row is reaching another character —
/// and on the layouts that type a letter there, it is reaching the digit.
@MainActor
@Test func theDigitRowHasNoSmallLetterToType() throws {
    let us = CasedKeys(layout: try #require(layout("com.apple.keylayout.US")))
    #expect(us.smallLetter(keyCode: digitKey, keyboardType: anyKeyboard, flags: []) == nil)
    // French types é there, and Shift types 2. Caps Lock types É, so Shift is not the
    // key's case switch even though the character it types has a case.
    let french = CasedKeys(layout: try #require(layout("com.apple.keylayout.French")))
    #expect(french.smallLetter(keyCode: digitKey, keyboardType: anyKeyboard, flags: []) == nil)
}

/// Turkish is why the layout is asked rather than the characters compared: it types `i`
/// and `İ` on one key, and `i` uppercases to `I` in every locale but that one. The
/// layout has no such trouble — `İ` is what its Caps Lock types there, so `i` is the
/// small letter to put back.
@MainActor
@Test func theTurkishDottedCapitalIsStillACase() throws {
    let keys = CasedKeys(layout: try #require(layout("com.apple.keylayout.Turkish")))
    #expect(
        keys.smallLetter(keyCode: turkishDottedI, keyboardType: anyKeyboard, flags: []) == "i"
    )
}

/// Keys that type nothing type the same nothing with Shift, so they have no small
/// letter and keep the Shift that selects text with them.
@MainActor
@Test func aKeyThatTypesNoCharacterHasNoSmallLetter() throws {
    let keys = CasedKeys(layout: try #require(layout("com.apple.keylayout.US")))
    #expect(keys.smallLetter(keyCode: arrowKey, keyboardType: anyKeyboard, flags: []) == nil)
    #expect(
        keys.smallLetter(
            keyCode: Int64(kVK_ANSI_KeypadClear),
            keyboardType: anyKeyboard,
            flags: []
        ) == nil
    )
}

/// The answers are kept, so a key held down does not go back to the layout on every
/// repeat. Asking twice has to answer the same either way.
@MainActor
@Test func askingTwiceAnswersTheSame() throws {
    let keys = CasedKeys(layout: try #require(layout("com.apple.keylayout.US")))
    #expect(keys.smallLetter(keyCode: letterKey, keyboardType: anyKeyboard, flags: []) == "a")
    #expect(keys.smallLetter(keyCode: letterKey, keyboardType: anyKeyboard, flags: []) == "a")
}

/// A keycode no keyboard sends is not a key the layout can be asked about.
@MainActor
@Test func aKeycodeOffTheKeyboardHasNoSmallLetter() throws {
    let keys = CasedKeys(layout: try #require(layout("com.apple.keylayout.US")))
    #expect(keys.smallLetter(keyCode: 70000, keyboardType: anyKeyboard, flags: []) == nil)
    #expect(keys.smallLetter(keyCode: -1, keyboardType: anyKeyboard, flags: []) == nil)
}

/// Following the input source is what the app does, and a reading of this Mac is not a
/// value to assert: it may be set to a layout with no cased keys at all.
@MainActor
@Test func theLayoutInForceCanBeAskedWithoutPinningOne() {
    let keys = CasedKeys()
    keys.start()
    _ = keys.smallLetter(keyCode: letterKey, keyboardType: anyKeyboard, flags: [])
    keys.stop()
}
