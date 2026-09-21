import CapsAwakeCore
import Foundation
import Testing

@testable import CapsAwake

/// The Mac's own sleep time is read by forking `pmset`, so it is kept rather than read
/// anew on every five-second reconcile tick. The staleness rule is the whole of the
/// type, and it is time-dependent — hence the injected clock, without which none of
/// this could be asserted without sleeping in a test.

/// What the Mac would answer, and how often it was asked.
///
/// `nonisolated` and lock-guarded, because the cache does its reading off the main
/// actor — which is the whole reason the real one forks `pmset` there.
private nonisolated final class FakeMac: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: [PowerSource: Int] = [.battery: 10, .adapter: 30]
    private var asked = 0
    private var clockValue = Date(timeIntervalSince1970: 1_000_000)

    var reply: [PowerSource: Int] {
        get { lock.withLock { answer } }
        set { lock.withLock { answer = newValue } }
    }

    var reads: Int { lock.withLock { asked } }
    var now: Date { lock.withLock { clockValue } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { clockValue += seconds }
    }

    func clock() -> Date { now }

    func read() -> [PowerSource: Int] {
        lock.withLock {
            asked += 1
            return answer
        }
    }
}

/// Drives the cache to the point where its in-flight read has landed.
private func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

@MainActor
@Test func theFirstAskReadsTheMac() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)

    #expect(cache.minutes(for: .battery) == nil)
    await settle()
    #expect(cache.minutes(for: .battery) == 10)
    #expect(cache.minutes(for: .adapter) == 30)
}

/// The point of the cache: five-second ticks must not each fork `pmset`.
@MainActor
@Test func aFreshReadingIsNotTakenAgain() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)
    _ = cache.minutes(for: .battery)
    await settle()

    mac.reply = [.battery: 99]
    for _ in 0..<10 {
        mac.advance(5)
        _ = cache.minutes(for: .battery)
    }
    await settle()

    #expect(cache.minutes(for: .battery) == 10)
}

@MainActor
@Test func aReadingThatHasAgedIsTakenAgain() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)
    _ = cache.minutes(for: .battery)
    await settle()

    mac.reply = [.battery: 45]
    mac.advance(301)
    _ = cache.minutes(for: .battery)
    await settle()

    #expect(cache.minutes(for: .battery) == 45)
}

/// A read that came back with nothing has not read the Mac, so the cache must not count
/// it as fresh. It used to: the stamp was written before the read rather than after, so
/// one failure put the cache to sleep for five minutes holding nothing.
@MainActor
@Test func aFailedReadDoesNotCountAsAFreshOne() async {
    let mac = FakeMac()
    mac.reply = [:]
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)

    _ = cache.minutes(for: .battery)
    await settle()
    #expect(cache.minutes(for: .battery) == nil)

    // The Mac answers this time, and the cache is still willing to ask — no time has
    // passed at all.
    mac.reply = [.battery: 15]
    _ = cache.minutes(for: .battery)
    await settle()
    #expect(cache.minutes(for: .battery) == 15)
}

/// Settings quotes the sleep time back at the user, so opening it reads again rather
/// than showing whatever was in hand.
@MainActor
@Test func aForcedRefreshDoesNotWaitForTheReadingToAge() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)
    _ = cache.minutes(for: .battery)
    await settle()

    mac.reply = [.battery: 5]
    cache.refresh(source: .battery)
    await settle()

    #expect(cache.minutes(for: .battery) == 5)
}

@MainActor
@Test func aChangedReadingIsReported() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)
    var reported: [Int?] = []
    cache.onChange = { reported.append($0) }

    _ = cache.minutes(for: .battery)
    await settle()

    mac.reply = [.battery: 20]
    cache.refresh(source: .battery)
    await settle()

    // Once for learning it, once for it changing — and not again for the same value.
    cache.refresh(source: .battery)
    await settle()

    #expect(reported == [10, 20])
}

@MainActor
@Test func stoppingCancelsAReadInFlight() async {
    let mac = FakeMac()
    let cache = SleepTimerCache(maxAge: 300, now: mac.clock, read: mac.read)

    _ = cache.minutes(for: .battery)
    cache.stop()
    await settle()

    // `stop()` runs on the quit path, where an outstanding read must not come back and
    // publish into a model the app has finished with.
    #expect(cache.minutes(for: .battery) == nil)
}
