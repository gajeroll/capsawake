import CapsAwakeCore
import SwiftUI

struct GeneralSection: View {
    @AppStorage(UserPreferenceKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(UserPreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(UserPreferenceKey.language) private var language = AppLanguage.defaultLanguage
        .rawValue

    var body: some View {
        Section {
            Toggle(isOn: $launchAtLogin) {
                Text("launch_at_login")
            }
            Toggle(isOn: $showMenuBarIcon) {
                Text("show_menu_bar_icon")
            }
            Picker(selection: $language) {
                Text(verbatim: "English").tag(AppLanguage.english.rawValue)
                Text(verbatim: "日本語").tag(AppLanguage.japanese.rawValue)
            } label: {
                Text("language")
            }
        } header: {
            Text("settings_section_general")
        }
    }
}
