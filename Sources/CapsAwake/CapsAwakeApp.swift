import CapsAwakeCore
import CapsAwakeUI
import SwiftUI

@main
struct CapsAwakeApp: App {
    /// Unlike `NSApplication.delegate`, the adaptor holds the delegate strongly.
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    @AppStorage(UserPreferenceKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(UserPreferenceKey.language) private var language = AppLanguage.defaultLanguage
        .rawValue

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent(model: controller.model)
                .environment(\.locale, Locale(identifier: language))
        } label: {
            MenuBarLabel(model: controller.model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView(model: controller.model)
                .environment(\.locale, Locale(identifier: language))
        }
    }
}
