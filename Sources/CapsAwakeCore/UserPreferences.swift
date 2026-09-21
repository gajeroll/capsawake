import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"

    public static var defaultLanguage: AppLanguage {
        let code = Locale.preferredLanguages.first?
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased()
        return code == "ja" ? .japanese : .english
    }
}

public enum UserPreferenceKey {
    public static let dedicatedMode = "DedicatedMode"
    public static let showMenuBarIcon = "ShowMenuBarIcon"
    public static let displaySleepOnLidClose = "DisplaySleepOnLidClose"
    public static let removeCapsLockDelay = "RemoveCapsLockDelay"
    public static let capitalsModifiers = "CapitalsModifiers"
    public static let shiftTypesSmallLetters = "ShiftTypesSmallLetters"
    public static let launchAtLogin = "LaunchAtLogin"
    public static let changeEnergyMode = "ChangeEnergyMode"
    public static let separateEnergyModes = "SeparateEnergyModes"
    public static let energyMode = "EnergyMode"
    public static let energyModeOnBattery = "EnergyModeOnBattery"
    public static let energyModeOnAdapter = "EnergyModeOnAdapter"
    public static let awakePastSleepTime = "AwakePastSleepTime"
    public static let awakeBatteryFloor = "AwakeBatteryFloor"
    public static let language = "Language"
    public static let didCompleteOnboarding = "DidCompleteOnboarding"
}

@MainActor
public enum UserPreferences {
    private static let defaults = UserDefaults.standard

    public static func registerDefaults() {
        defaults.register(defaults: [
            UserPreferenceKey.dedicatedMode: false,
            UserPreferenceKey.showMenuBarIcon: true,
            UserPreferenceKey.displaySleepOnLidClose: true,
            UserPreferenceKey.removeCapsLockDelay: true,
            UserPreferenceKey.capitalsModifiers: CapsLockModifiers.shift.rawValue,
            UserPreferenceKey.shiftTypesSmallLetters: false,
            UserPreferenceKey.launchAtLogin: true,
            UserPreferenceKey.changeEnergyMode: true,
            UserPreferenceKey.separateEnergyModes: false,
            UserPreferenceKey.energyMode: EnergyMode.low.rawValue,
            UserPreferenceKey.energyModeOnBattery: EnergyMode.low.rawValue,
            UserPreferenceKey.energyModeOnAdapter: EnergyMode.low.rawValue,
            UserPreferenceKey.awakePastSleepTime: AwakePastSleepTime.always.rawValue,
            UserPreferenceKey.awakeBatteryFloor: AwakeBatteryFloor.standard,
            UserPreferenceKey.language: AppLanguage.defaultLanguage.rawValue,
            UserPreferenceKey.didCompleteOnboarding: false,
        ])
    }

    public static var dedicatedMode: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.dedicatedMode) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.dedicatedMode) }
    }

    public static var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.showMenuBarIcon) }
    }

    public static var displaySleepOnLidClose: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.displaySleepOnLidClose) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.displaySleepOnLidClose) }
    }

    /// Whether to take out the delay macOS puts in front of the Caps Lock key while
    /// CapsAwake is running. It is a keyboard-wide setting, not one of ours, so it is
    /// read before it is changed and put back on quit.
    public static var removeCapsLockDelay: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.removeCapsLockDelay) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.removeCapsLockDelay) }
    }

    /// Which modifiers, held with Caps Lock, switch capitals rather than CapsAwake.
    /// Empty means nothing does, and Caps Lock is CapsAwake's however it is pressed.
    public static var capitalsModifiers: CapsLockModifiers {
        get {
            CapsLockModifiers(
                rawValue: defaults.integer(forKey: UserPreferenceKey.capitalsModifiers)
            )
        }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.capitalsModifiers) }
    }

    /// Whether, while capitals are locked on, holding Shift types the small letter
    /// the way Windows' Caps Lock does. The Mac's own Caps Lock answers Shift with
    /// the capital, so the reversal is off until asked for.
    public static var shiftTypesSmallLetters: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.shiftTypesSmallLetters) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.shiftTypesSmallLetters) }
    }

    public static var launchAtLogin: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.launchAtLogin) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.launchAtLogin) }
    }

    public static var changeEnergyMode: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.changeEnergyMode) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.changeEnergyMode) }
    }

    public static var separateEnergyModes: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.separateEnergyModes) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.separateEnergyModes) }
    }

    public static var energyMode: EnergyMode {
        get { mode(forKey: UserPreferenceKey.energyMode) }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.energyMode) }
    }

    public static var energyModeOnBattery: EnergyMode {
        get { mode(forKey: UserPreferenceKey.energyModeOnBattery) }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.energyModeOnBattery) }
    }

    public static var energyModeOnAdapter: EnergyMode {
        get { mode(forKey: UserPreferenceKey.energyModeOnAdapter) }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.energyModeOnAdapter) }
    }

    /// The mode to impose per power source, or `nil` to leave the Energy Mode alone.
    /// The two sources share one setting unless the user split them.
    public static var energyModePlan: EnergyModePlan? {
        guard changeEnergyMode else { return nil }
        guard separateEnergyModes else { return EnergyModePlan(energyMode) }
        return EnergyModePlan(battery: energyModeOnBattery, adapter: energyModeOnAdapter)
    }

    private static func mode(forKey key: String) -> EnergyMode {
        EnergyMode(rawValue: defaults.string(forKey: key) ?? "") ?? .low
    }

    /// What to do when the Mac's own sleep time arrives with nobody at the keyboard.
    public static var awakePastSleepTime: AwakePastSleepTime {
        get {
            AwakePastSleepTime(
                rawValue: defaults.string(forKey: UserPreferenceKey.awakePastSleepTime) ?? ""
            ) ?? .always
        }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.awakePastSleepTime) }
    }

    /// The battery level to keep going down to, or `nil` for any level.
    ///
    /// Stored as a percentage with zero standing for no level at all, so the setting
    /// is one value rather than a switch and a value that can disagree.
    public static var awakeBatteryFloor: Int? {
        get {
            let stored = defaults.integer(forKey: UserPreferenceKey.awakeBatteryFloor)
            return stored > 0 ? stored : nil
        }
        set { defaults.set(newValue ?? 0, forKey: UserPreferenceKey.awakeBatteryFloor) }
    }

    public static var language: AppLanguage {
        get {
            AppLanguage(rawValue: defaults.string(forKey: UserPreferenceKey.language) ?? "")
                ?? AppLanguage.defaultLanguage
        }
        set { defaults.set(newValue.rawValue, forKey: UserPreferenceKey.language) }
    }

    public static var didCompleteOnboarding: Bool {
        get { defaults.bool(forKey: UserPreferenceKey.didCompleteOnboarding) }
        set { defaults.set(newValue, forKey: UserPreferenceKey.didCompleteOnboarding) }
    }

    public static func snapshot() -> PreferencesSnapshot {
        PreferencesSnapshot(
            dedicatedModeEnabled: dedicatedMode,
            displaySleepOnLidClose: displaySleepOnLidClose,
            energyModePlan: energyModePlan,
            awakePastSleepTime: awakePastSleepTime,
            awakeBatteryFloor: awakeBatteryFloor
        )
    }
}
