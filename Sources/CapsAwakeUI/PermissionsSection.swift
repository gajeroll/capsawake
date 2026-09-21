import CapsAwakeCore
import SwiftUI

/// What CapsAwake has been allowed to do, listed whether or not anything is
/// missing.
///
/// Showing only the failures meant the window said nothing at all when everything
/// was fine, and there was no way to check what had been granted without breaking
/// something first.
///
/// Near the bottom because a granted permission is something to read, not something
/// to set. What is missing does not wait to be found here: it is announced at the top
/// of the window and in the menu.
struct PermissionsSection: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(model.systemAccess) { item in
                SystemAccessRow(item: item, model: model)
            }
        } header: {
            Text("settings_section_permissions")
        } footer: {
            Text("settings_section_permissions_help")
                .foregroundStyle(.secondary)
        }
    }
}
