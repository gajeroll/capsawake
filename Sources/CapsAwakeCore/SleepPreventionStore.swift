import Foundation

/// Owns `SleepPreventionState` and is the only way to mutate it.
///
/// Environment changes (lid, display, LED observations) must arrive as intents.
/// That keeps the reducer as the single source of truth and makes "write state
/// directly from a poll" a compile-time impossibility for callers that only hold
/// a store.
@MainActor
public final class SleepPreventionStore {
    public private(set) var state: SleepPreventionState

    private let perform: @MainActor ([Effect]) -> Void

    public init(
        initial: SleepPreventionState = SleepPreventionState(),
        perform: @escaping @MainActor ([Effect]) -> Void
    ) {
        self.state = initial
        self.perform = perform
    }

    public func dispatch(_ intent: Intent) {
        let result = SleepPreventionReducer.reduce(state: state, intent: intent)
        state = result.state
        if !result.effects.isEmpty {
            perform(result.effects)
        }
    }
}
