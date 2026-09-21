import CapsAwakeCore
import SwiftUI

/// The Energy Mode to switch to while sleep prevention is on.
///
/// macOS keeps the mode per power source, so the two can be split. They share one
/// setting by default, which is what most people expect from a single switch.
struct EnergyModeSection: View {
    let energy: EnergyModeModel

    @AppStorage(UserPreferenceKey.changeEnergyMode) private var changeEnergyMode = true
    @AppStorage(UserPreferenceKey.separateEnergyModes) private var separateEnergyModes = false
    @AppStorage(UserPreferenceKey.energyMode) private var sharedMode = EnergyMode.low.rawValue
    @AppStorage(UserPreferenceKey.energyModeOnBattery) private var batteryMode = EnergyMode.low
        .rawValue
    @AppStorage(UserPreferenceKey.energyModeOnAdapter) private var adapterMode = EnergyMode.low
        .rawValue

    var body: some View {
        Section {
            Toggle(isOn: $changeEnergyMode) {
                Text("change_energy_mode")
            }
            if changeEnergyMode {
                Toggle(isOn: $separateEnergyModes) {
                    Text("separate_energy_modes")
                }
                if separateEnergyModes {
                    modePicker("energy_mode_battery", selection: $batteryMode)
                    modePicker("energy_mode_adapter", selection: $adapterMode)
                } else {
                    modePicker("energy_mode", selection: $sharedMode)
                }
            }
        } header: {
            Text("energy_mode_section")
        } footer: {
            Text("energy_mode_help")
                .foregroundStyle(.secondary)
        }
    }

    private func modePicker(
        _ titleKey: LocalizedStringKey,
        selection: Binding<String>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(energy.offeredModes, id: \.self) { mode in
                Text(mode.labelKey).tag(mode.rawValue)
            }
        } label: {
            Text(titleKey)
        }
    }
}

extension EnergyMode {
    var labelKey: LocalizedStringKey {
        switch self {
        case .automatic: "energy_mode_automatic"
        case .low: "energy_mode_low"
        case .high: "energy_mode_high"
        }
    }
}
