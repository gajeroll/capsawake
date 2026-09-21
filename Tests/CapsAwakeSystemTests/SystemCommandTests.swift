import Testing

@testable import CapsAwakeSystem

/// Everything CapsAwake asks of `pmset` and `hidutil` goes through here, and the daemon
/// runs it as root — so what matters is that it always comes back.

@Test func aCommandReportsWhatItPrinted() {
    let result = SystemCommand.run("/bin/echo", ["hello"])
    #expect(result.status == 0)
    #expect(result.stdout == "hello")
}

@Test func aFailingCommandReportsItsStatus() {
    let result = SystemCommand.run("/usr/bin/false", [])
    #expect(result.status != 0)
}

@Test func aCommandThatIsNotThereIsNotACrash() {
    let result = SystemCommand.run("/nonexistent/capsawake-not-a-tool", [])
    #expect(result.status == -1)
    #expect(!result.stderr.isEmpty)
}

/// Arguments are handed over as an array, never as a string for a shell to read, so
/// there is no parsing step for anything to be injected into.
@Test func argumentsAreNotRunThroughAShell() {
    let result = SystemCommand.run("/bin/echo", ["a; rm -rf /", "$(whoami)", "`id`"])
    #expect(result.status == 0)
    #expect(result.stdout == "a; rm -rf / $(whoami) `id`")
}

/// The reason the pipes are drained before waiting rather than after.
///
/// A pipe holds about 64 KB. A child that fills one blocks writing to it, and a parent
/// that waits for the child to exit before reading waits forever. Nothing CapsAwake runs
/// prints this much today — but the deadlock would be in the root daemon, mid-write.
@Test func aCommandThatPrintsMoreThanAPipeHoldsStillReturns() {
    // `seq 1 200000` prints well over a megabyte and then exits, so this hangs on the
    // old ordering and finishes on the new one.
    let result = SystemCommand.run("/usr/bin/seq", ["1", "200000"])
    #expect(result.status == 0)
    #expect(result.stdout.count > 1_000_000)
    #expect(result.stdout.hasSuffix("200000"))
}
