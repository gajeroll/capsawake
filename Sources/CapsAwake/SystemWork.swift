import Foundation

/// Runs blocking system work — a `pmset` or `hidutil` fork, a walk through the I/O
/// registry — somewhere other than the main actor, and comes back with the answer.
///
/// `Task.detached` rather than a plain `Task`: a task created from a main-actor
/// context inherits that actor, so the fork would happen on the thread that is meant
/// to be drawing the menu bar.
func offMainActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached { work() }.value
}

/// A repeating timer on the main run loop, in common modes so it keeps firing while a
/// menu is open.
///
/// The tolerance is the point of having this in one place. A timer with none asks
/// macOS to wake the Mac exactly on the second, which is a strange thing to do
/// repeatedly in an app whose subject is how much the Mac is awake.
@MainActor
func repeatingTimer(
    every interval: TimeInterval,
    tolerance: TimeInterval,
    run: @escaping @MainActor () -> Void
) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in
        Task { @MainActor in run() }
    }
    timer.tolerance = tolerance
    RunLoop.main.add(timer, forMode: .common)
    return timer
}
