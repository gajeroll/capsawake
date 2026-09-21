import CapsAwakeCore
import Foundation

/// The preferences that need work outside SwiftUI when they change.
///
/// The views read and write preferences straight through `@AppStorage`, so
/// `UserDefaults.didChangeNotification` is the channel between the UI and the rest of
/// the app. It fires for every key, including ones only the UI cares about, and says
/// nothing about which one moved — hence a snapshot, compared against the last.
struct PreferenceSnapshot: Equatable {
    var dedicatedMode: Bool
    var displaySleepOnLidClose: Bool
    var launchAtLogin: Bool
    var removeCapsLockDelay: Bool
    var capitalsModifiers: CapsLockModifiers
    var shiftTypesSmallLetters: Bool
    var energyModePlan: EnergyModePlan?
    var awakePastSleepTime: AwakePastSleepTime
    var awakeBatteryFloor: Int?

    init(
        dedicatedMode: Bool = false,
        displaySleepOnLidClose: Bool = true,
        launchAtLogin: Bool = true,
        removeCapsLockDelay: Bool = true,
        capitalsModifiers: CapsLockModifiers = .shift,
        shiftTypesSmallLetters: Bool = false,
        energyModePlan: EnergyModePlan? = nil,
        awakePastSleepTime: AwakePastSleepTime = .always,
        awakeBatteryFloor: Int? = AwakeBatteryFloor.standard
    ) {
        self.dedicatedMode = dedicatedMode
        self.displaySleepOnLidClose = displaySleepOnLidClose
        self.launchAtLogin = launchAtLogin
        self.removeCapsLockDelay = removeCapsLockDelay
        self.capitalsModifiers = capitalsModifiers
        self.shiftTypesSmallLetters = shiftTypesSmallLetters
        self.energyModePlan = energyModePlan
        self.awakePastSleepTime = awakePastSleepTime
        self.awakeBatteryFloor = awakeBatteryFloor
    }

    /// The preferences as they stand.
    @MainActor
    static func current() -> Self {
        PreferenceSnapshot(
            dedicatedMode: UserPreferences.dedicatedMode,
            displaySleepOnLidClose: UserPreferences.displaySleepOnLidClose,
            launchAtLogin: UserPreferences.launchAtLogin,
            removeCapsLockDelay: UserPreferences.removeCapsLockDelay,
            capitalsModifiers: UserPreferences.capitalsModifiers,
            shiftTypesSmallLetters: UserPreferences.shiftTypesSmallLetters,
            energyModePlan: UserPreferences.energyModePlan,
            awakePastSleepTime: UserPreferences.awakePastSleepTime,
            awakeBatteryFloor: UserPreferences.awakeBatteryFloor
        )
    }
}

/// What actually changed, so each reaction runs when its own preference moved rather
/// than whenever any of them did.
enum PreferenceChange: CaseIterable {
    case dedicatedMode
    case capitalsModifiers
    case shiftTypesSmallLetters
    case launchAtLogin
    case capsLockDelay
    /// Anything the state machine reads: the two ends of staying awake, the Energy
    /// Mode plan, whether the lid closing should sleep the display.
    case reducerInput

    static func between(_ old: PreferenceSnapshot, _ new: PreferenceSnapshot) -> Set<Self> {
        var changed: Set<Self> = []
        if old.dedicatedMode != new.dedicatedMode { changed.insert(.dedicatedMode) }
        if old.capitalsModifiers != new.capitalsModifiers { changed.insert(.capitalsModifiers) }
        if old.shiftTypesSmallLetters != new.shiftTypesSmallLetters {
            changed.insert(.shiftTypesSmallLetters)
        }
        if old.launchAtLogin != new.launchAtLogin { changed.insert(.launchAtLogin) }
        if old.removeCapsLockDelay != new.removeCapsLockDelay { changed.insert(.capsLockDelay) }
        if old.dedicatedMode != new.dedicatedMode
            || old.displaySleepOnLidClose != new.displaySleepOnLidClose
            || old.energyModePlan != new.energyModePlan
            || old.awakePastSleepTime != new.awakePastSleepTime
            || old.awakeBatteryFloor != new.awakeBatteryFloor
        {
            changed.insert(.reducerInput)
        }
        return changed
    }
}

/// Watches `UserDefaults` and reports what moved.
@MainActor
final class PreferenceWatcher {
    /// Never called with an empty set: a notification that changed nothing we care
    /// about is not a change.
    var onChange: ((Set<PreferenceChange>) -> Void)?

    private var last: PreferenceSnapshot?
    private var observer: NSObjectProtocol?

    /// Takes the first snapshot without reporting it. At launch everything is applied
    /// unconditionally, and reporting it here would do all of it twice.
    func start() {
        last = .current()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
    }

    private func check() {
        let snapshot = PreferenceSnapshot.current()
        defer { last = snapshot }
        guard let last, last != snapshot else { return }
        let changes = PreferenceChange.between(last, snapshot)
        guard !changes.isEmpty else { return }
        onChange?(changes)
    }
}
