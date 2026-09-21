import CapsAwakeCore
import CoreGraphics
import Testing

@testable import CapsAwakeSystem

private func action(
    _ flags: CGEventFlags,
    capitals: CapsLockModifiers = .shift,
    eventType: CGEventType = .flagsChanged,
    keyCode: Int64 = CapsLockFilterPolicy.capsLockKeyCode,
    isRecording: Bool = false
) -> CapsLockKeyAction {
    CapsLockFilterPolicy.action(
        eventType: eventType,
        keyCode: keyCode,
        flags: flags,
        capitalsModifiers: capitals,
        isRecording: isRecording
    )
}

@Test func capsLockOnItsOwnIsTheCapsAwakeSwitch() {
    #expect(action([.maskAlphaShift]) == .toggleCapsAwake)
}

@Test func theChosenCombinationIsThePlainCapsLock() {
    #expect(action([.maskAlphaShift, .maskShift]) == .toggleCapsLockTyping)
    #expect(
        action([.maskAlphaShift, .maskControl, .maskCommand], capitals: [.control, .command])
            == .toggleCapsLockTyping
    )
}

/// Holding more than the combination asks for is not the combination, so it reaches
/// the switch the key is otherwise for rather than doing both things at once.
@Test func aCombinationHasToMatchExactly() {
    #expect(action([.maskAlphaShift, .maskShift, .maskCommand]) == .toggleCapsAwake)
    #expect(
        action([.maskAlphaShift, .maskControl], capitals: [.control, .command])
            == .toggleCapsAwake
    )
}

/// With no keys chosen, every press is CapsAwake's and capitals are left to the UI.
@Test func withoutACombinationEveryPressIsTheSwitch() {
    #expect(action([.maskAlphaShift], capitals: []) == .toggleCapsAwake)
    #expect(action([.maskAlphaShift, .maskShift], capitals: []) == .toggleCapsAwake)
}

/// While Settings waits for the combination, the press is being asked about rather
/// than made: neither switch moves, whatever the press looks like.
@Test func whileListeningAPressOnlyReportsTheKeysHeldWithIt() {
    #expect(
        action([.maskAlphaShift, .maskControl, .maskAlternate], isRecording: true)
            == .recordCombination([.control, .option])
    )
    // The combination already in force, and Caps Lock on its own, both report.
    #expect(action([.maskAlphaShift, .maskShift], isRecording: true) == .recordCombination(.shift))
    #expect(action([.maskAlphaShift], isRecording: true) == .recordCombination([]))
}

@Test func otherKeysAreLeftAlone() {
    #expect(action([.maskShift], eventType: .keyDown, keyCode: 0) == .notCapsLock)
    #expect(action([], eventType: .keyDown) == .notCapsLock)
    // Listening does not turn the rest of the keyboard into the combination.
    #expect(
        action([.maskShift], eventType: .keyDown, keyCode: 0, isRecording: true) == .notCapsLock
    )
}

@Test func theModifiersHeldAreReadOffTheEvent() {
    #expect(
        CapsLockFilterPolicy.heldModifiers([.maskAlphaShift, .maskShift, .maskAlternate])
            == [.shift, .option]
    )
    #expect(CapsLockFilterPolicy.heldModifiers([.maskAlphaShift]) == [])
}

/// Shift+Caps Lock, with sleep prevention off: the press engages the lock, the app
/// puts it back, and the release reports it there.
@Test func theReleaseOfAKeyIsNotAPressOfItsOwn() {
    var reader = CapsLockPressReader(lockOn: false)
    let press = reader.isPress(lockOn: true)
    reader.note(lockOn: false)
    let release = reader.isPress(lockOn: false)
    #expect(press)
    #expect(!release)
}

/// Nothing is timed, so the key can be held as long as you like.
@Test func holdingTheKeyIsStillOnePress() {
    var reader = CapsLockPressReader(lockOn: false)
    _ = reader.isPress(lockOn: true)
    reader.note(lockOn: false)
    let release = reader.isPress(lockOn: false)
    let next = reader.isPress(lockOn: true)
    #expect(!release)
    #expect(next)
}

/// Repeating the key as fast as Cmd+V: every press counts.
@Test func pressesInQuickSuccessionAllCount() {
    var reader = CapsLockPressReader(lockOn: false)
    for _ in 0..<5 {
        let press = reader.isPress(lockOn: true)
        reader.note(lockOn: false)
        let release = reader.isPress(lockOn: false)
        #expect(press)
        #expect(!release)
    }
}

/// Whatever the lock is doing when the filter starts, the first press is a press.
@Test func theFirstEventIsAlwaysAPress() {
    var unknown = CapsLockPressReader()
    let press = unknown.isPress(lockOn: false)
    #expect(press)
}

@Test func capitalizingAddsTheCapsLockFlagTheHardwareIsNotHolding() {
    #expect(CapsLockFilterPolicy.capitalizedFlags([]).contains(.maskAlphaShift))
    // The hardware lock is the sleep-prevention switch, so it is often already on.
    #expect(CapsLockFilterPolicy.capitalizedFlags([.maskAlphaShift]).contains(.maskAlphaShift))
    // The rest of what was held is the user's.
    #expect(CapsLockFilterPolicy.capitalizedFlags([.maskShift]).contains(.maskShift))
    #expect(CapsLockFilterPolicy.capitalizedFlags([.maskAlternate]).contains(.maskAlternate))
}

/// The layout is worth asking only about a key that types something. A modifier going
/// down or up is what tells other apps Shift is held, and a shortcut is spelled with
/// the Shift it holds: ⌘⇧S is not ⌘S.
@Test func onlyATypedKeyAsksTheLayoutAboutShift() {
    #expect(CapsLockFilterPolicy.shiftMayBeCapitalizing(eventType: .keyDown, flags: [.maskShift]))
    #expect(
        CapsLockFilterPolicy.shiftMayBeCapitalizing(
            eventType: .keyDown,
            flags: [.maskShift, .maskAlternate]
        )
    )
    #expect(!CapsLockFilterPolicy.shiftMayBeCapitalizing(eventType: .keyDown, flags: []))
    #expect(
        !CapsLockFilterPolicy.shiftMayBeCapitalizing(
            eventType: .flagsChanged,
            flags: [.maskShift]
        )
    )
    #expect(
        !CapsLockFilterPolicy.shiftMayBeCapitalizing(
            eventType: .keyDown,
            flags: [.maskShift, .maskCommand]
        )
    )
    #expect(
        !CapsLockFilterPolicy.shiftMayBeCapitalizing(
            eventType: .keyDown,
            flags: [.maskShift, .maskControl]
        )
    )
}

@Test func sanitizingRemovesOnlyTheCapsLockFlag() {
    let sanitized = CapsLockFilterPolicy.sanitizedFlags([.maskAlphaShift, .maskShift])
    #expect(!sanitized.contains(.maskAlphaShift))
    #expect(sanitized.contains(.maskShift))
}
