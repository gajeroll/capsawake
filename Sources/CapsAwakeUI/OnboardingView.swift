import CapsAwakeCore
import SwiftUI

/// First run, in the order the Mac actually needs things.
///
/// The permissions come first and one at a time, because they are the only part
/// the user cannot fix later without knowing where to look, and because a
/// preference that depends on a permission is meaningless until it is granted.
/// Preferences are last and few: everything else is in Settings.
struct OnboardingView: View {
    let model: AppModel
    let onDone: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            Form {
                switch step {
                case .welcome: WelcomeStep()
                case .backgroundDaemon: BackgroundDaemonStep(model: model)
                case .capitals: CapitalsStep(model: model)
                case .preferences: PreferencesStep(model: model)
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 460, height: 460)
    }

    private var footer: some View {
        HStack {
            Text("onboarding_step \(step.number) \(OnboardingStep.allCases.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if let previous = step.previous {
                Button {
                    step = previous
                } label: {
                    Text("onboarding_back")
                }
            }
            Button {
                if let next = step.next { step = next } else { onDone() }
            } label: {
                Text(step.next == nil ? "get_started" : "onboarding_continue")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case backgroundDaemon
    case capitals
    case preferences

    var number: Int { rawValue + 1 }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

private struct WelcomeStep: View {
    var body: some View {
        Section {
            Text("onboarding_title")
                .font(.headline)
            Text("onboarding_body")
                .foregroundStyle(.secondary)
            Text("onboarding_permissions_intro")
                .foregroundStyle(.secondary)
        }
    }
}

/// The one permission CapsAwake cannot work without, so it gets a step of its own
/// and says plainly what happens if it is skipped.
private struct BackgroundDaemonStep: View {
    let model: AppModel

    var body: some View {
        Section {
            if let item = model.access(.backgroundDaemon) {
                AccessStepBody(item: item, model: model)
            }
        } header: {
            Text("access_daemon_title")
        } footer: {
            Text("onboarding_daemon_footer")
                .foregroundStyle(.secondary)
        }
    }
}

/// The choice that decides whether Accessibility is needed at all, with the
/// permission shown underneath it so the cost of the choice is visible while it is
/// being made rather than after.
private struct CapitalsStep: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.dedicatedMode) private var dedicatedMode = false

    var body: some View {
        Section {
            Text("onboarding_capitals_body")
                .foregroundStyle(.secondary)
            DedicatedModeToggle()
        } header: {
            Text("settings_section_caps_lock")
        }

        if dedicatedMode, let item = model.access(.accessibility) {
            Section {
                AccessStepBody(item: item, model: model)
            } header: {
                Text("access_accessibility_title")
            }
        }
    }
}

private struct PreferencesStep: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(UserPreferenceKey.changeEnergyMode) private var changeEnergyMode = true

    var body: some View {
        Section {
            if model.energy.isSupported {
                Toggle(isOn: $changeEnergyMode) {
                    Text("change_energy_mode")
                }
            }
            Toggle(isOn: $showMenuBarIcon) {
                Text("show_menu_bar_icon")
            }
        } header: {
            Text("settings_section_general")
        } footer: {
            Text("onboarding_preferences_footer")
                .foregroundStyle(.secondary)
        }
    }
}

/// A permission as an onboarding step: why it is wanted, what it costs to skip,
/// where it stands now, and the button that grants it.
private struct AccessStepBody: View {
    let item: SystemAccessItem
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.purposeKey)
            if let impactKey = item.impactKey {
                Text(impactKey)
                    .font(.callout)
                    .foregroundStyle(item.needsAttention ? item.tint : .secondary)
            }
            HStack {
                AccessStatusBadge(item: item)
                Spacer()
                if item.needsAttention {
                    Button {
                        model.resolve(item)
                    } label: {
                        Text(item.actionKey)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
