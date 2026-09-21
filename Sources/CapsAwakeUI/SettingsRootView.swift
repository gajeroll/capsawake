import CapsAwakeCore
import SwiftUI

/// Contents of the standard Settings window. Doubles as first-run onboarding so
/// there is only one place to explain how CapsAwake behaves.
public struct SettingsRootView: View {
    @AppStorage(UserPreferenceKey.didCompleteOnboarding) private var didCompleteOnboarding = false

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        if didCompleteOnboarding {
            MainSettingsView(model: model)
        } else {
            OnboardingView(model: model) { didCompleteOnboarding = true }
        }
    }
}

/// Every preference lives here, including the ones the menu also carries, so there
/// is one complete place to see how CapsAwake is configured.
///
/// The order runs from what the keyboard is doing now, through what the key does and
/// what happens while nobody is watching, down to the things that are read rather than
/// changed. Only the first section is conditional: a permission that needs doing
/// something about is announced at the top, while the permissions themselves stay
/// where they always are, near the bottom. A section that moved about depending on
/// the state of the Mac would be a section nobody could learn the position of.
struct MainSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            if !model.pendingAccess.isEmpty {
                AttentionSection(model: model)
            }
            SwitchSection(model: model)
            CapsLockSection(model: model)
            LidSection(model: model)
            AwakeRangeSection(model: model)
            if model.energy.isSupported {
                EnergyModeSection(energy: model.energy)
            }
            GeneralSection()
            PermissionsSection(model: model)
            AdvancedSection(model: model)
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }
}
