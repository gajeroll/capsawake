import CapsAwakeCore
import Testing

@testable import CapsAwakeSystem

@Test func parsesTheSleepTimePerPowerSource() {
    let output = """
        Battery Power:
         hibernatemode        3
         sleep                1
         displaysleep         2
        AC Power:
         hibernatemode        3
         sleep                30
         displaysleep         10
        """
    let minutes = SystemSleepTimer.parseMinutes(from: output)
    #expect(minutes[.battery] == 1)
    #expect(minutes[.adapter] == 30)
}

/// Zero is how macOS says never, and it has to survive as a reading: it is the
/// difference between a Mac with no sleep time to reach and one we failed to ask.
@Test func readsNeverSleepingAsZeroRatherThanMissing() {
    let output = """
        AC Power:
         sleep                0
        """
    #expect(SystemSleepTimer.parseMinutes(from: output)[.adapter] == 0)
}

/// `pmset` prints the timer we want alongside two others whose names contain it, and
/// a switch whose name begins with it.
@Test func doesNotMistakeTheOtherSleepLinesForTheSleepTime() {
    let output = """
        AC Power:
         Sleep On Power Button 1
         displaysleep         10
         disksleep            0
        """
    #expect(SystemSleepTimer.parseMinutes(from: output).isEmpty)
}

/// The line carries a note about what is holding sleep off while something is, which
/// is exactly when CapsAwake is running.
@Test func readsTheSleepTimeThroughTheAssertionNote() {
    let output = """
        AC Power:
         sleep                20 (sleep prevented by CapsAwake, powerd)
        """
    #expect(SystemSleepTimer.parseMinutes(from: output)[.adapter] == 20)
}
