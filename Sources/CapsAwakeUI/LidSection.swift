import CapsAwakeCore
import SwiftUI

struct LidSection: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.displaySleepOnLidClose) private var displaySleepOnLidClose = true

    var body: some View {
        Section {
            Toggle(isOn: $displaySleepOnLidClose) {
                Text("display_sleep_on_lid_close")
            }
            if model.lidCloseWarning {
                Text("lid_close_may_sleep_warning")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings_section_lid")
        }
    }
}
