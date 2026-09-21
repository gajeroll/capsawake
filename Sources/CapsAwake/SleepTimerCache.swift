import CapsAwakeCore
import CapsAwakeSystem
import Foundation

/// The Mac's own sleep time for each power source, kept rather than read anew.
///
/// It changes only when the user changes it in System Settings, so a reading a few
/// minutes old is a reading — while forking `pmset` on every reconcile tick would be a
/// process every five seconds for a number that hardly ever moves. Anything that could
/// have changed it — a new power source, the Settings window opening — asks for a fresh
/// one.
@MainActor
final class SleepTimerCache {
    /// Called when the reading for the source last asked about changes, so Settings can
    /// quote it back.
    var onChange: ((Int?) -> Void)?

    private let maxAge: TimeInterval
    private let now: () -> Date
    private let read: @Sendable () -> [PowerSource: Int]

    private var readings: [PowerSource: Int] = [:]
    private var readAt: Date?
    private var inFlight: Task<Void, Never>?

    /// The reader is injected so the staleness rule can be tested without forking
    /// `pmset` — and so a test can say what the Mac replied.
    init(
        maxAge: TimeInterval = 300,
        now: @escaping () -> Date = Date.init,
        read: @escaping @Sendable () -> [PowerSource: Int] = { SystemSleepTimer.minutes() }
    ) {
        self.maxAge = maxAge
        self.now = now
        self.read = read
    }

    /// The sleep time for `source` in minutes, with zero meaning the Mac is set never
    /// to sleep and `nil` meaning it has not been read yet.
    ///
    /// The caller gets whatever reading is in hand; a stale one is refreshed behind them
    /// and the next caller has it.
    func minutes(for source: PowerSource) -> Int? {
        refresh(source: source, force: false)
        return readings[source]
    }

    /// Reads again whether or not the cache has aged, for a caller that knows the
    /// reading may have changed underneath it.
    func refresh(source: PowerSource) {
        refresh(source: source, force: true)
    }

    func stop() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func refresh(source: PowerSource, force: Bool) {
        if !force, let readAt, now().timeIntervalSince(readAt) < maxAge { return }
        // One read at a time. Without this a burst of preference changes each started
        // its own `pmset` fork.
        inFlight?.cancel()
        let read = read
        inFlight = Task { [weak self] in
            // Forks `pmset`, so it stays off the main actor.
            let minutes = await offMainActor { read() }
            guard !Task.isCancelled, let self else { return }
            self.inFlight = nil
            self.adopt(minutes, for: source)
        }
    }

    private func adopt(_ minutes: [PowerSource: Int], for source: PowerSource) {
        // A Mac that answered nothing has not been read. Stamping the cache fresh here
        // would put it to sleep for the whole of `maxAge` with nothing in it — which is
        // what happened while the stamp was written before the read rather than after.
        guard !minutes.isEmpty else { return }
        readAt = now()
        let previous = readings[source]
        readings = minutes
        guard readings[source] != previous else { return }
        onChange?(readings[source])
    }
}
