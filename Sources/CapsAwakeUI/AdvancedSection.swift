import CapsAwakeCore
import SwiftUI

struct AdvancedSection: View {
    let model: AppModel

    var body: some View {
        Section {
            Button {
                model.onRestart?()
            } label: {
                Text("restart")
            }
        } header: {
            Text("settings_section_advanced")
        } footer: {
            Text("restart_help")
                .foregroundStyle(.secondary)
        }
    }
}
