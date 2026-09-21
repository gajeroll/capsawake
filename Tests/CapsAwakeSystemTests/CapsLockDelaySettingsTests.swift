import Testing

@testable import CapsAwakeSystem

@Test func theDelayIsReadOffEveryKeyboardThatReportsOne() {
    let output = """
        RegistryID  Key                   Value
        100000d1b   CapsLockDelayOverride   0
        100000f42   CapsLockDelayOverride   75
        """
    #expect(
        CapsLockDelaySettings.parseValues(
            from: output,
            key: CapsLockDelaySettings.overrideProperty
        ) == [0, 75]
    )
}

/// A keyboard that does not carry the property reports `(null)`, and the header row
/// has a word where the value goes.
@Test func rowsWithoutANumberAreNotDelays() {
    let output = """
        RegistryID  Key                   Value
        100000662   CapsLockDelayOverride   (null)
        """
    #expect(
        CapsLockDelaySettings.parseValues(
            from: output,
            key: CapsLockDelaySettings.overrideProperty
        ).isEmpty
    )
}

/// `hidutil` reports whatever key it was asked for, so a reading of one property must
/// not be taken for another.
@Test func anotherPropertyIsNotTheDelay() {
    let output = """
        RegistryID  Key                   Value
        100000d1b   CapsLockDelay   75
        """
    #expect(
        CapsLockDelaySettings.parseValues(
            from: output,
            key: CapsLockDelaySettings.overrideProperty
        ).isEmpty
    )
}

/// Read from the I/O registry rather than through `hidutil`, and never zero: taking
/// the delay we impose for the keyboard's own would leave it removed for good.
@Test func theKeyboardReportsADelayToGoBackTo() {
    let delay = CapsLockDelaySettings.deviceDelay()
    #expect(delay > 0)
}
