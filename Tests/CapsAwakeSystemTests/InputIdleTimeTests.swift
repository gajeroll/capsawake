import Testing

@testable import CapsAwakeSystem

/// A reading, not a value: how long this machine has been idle is nobody's business
/// to assert, and a build machine may have no `IOHIDSystem` to ask at all.
@Test func idleTimeReaderDoesNotCrash() {
    if let seconds = InputIdleTime.seconds() {
        #expect(seconds >= 0)
    }
}
