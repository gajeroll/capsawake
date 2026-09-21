import CapsAwakeCore
import SwiftUI

/// The sleep prevention switch, at the top of the window because it is the one control
/// that is not a preference: it says what the keyboard is doing now, and the menu
/// carries the same switch.
///
/// The capitals switch is the other such control, and it sits in the Caps Lock section
/// instead: whether it exists at all depends on the preference there, and the same
/// paragraph that grants the key explains what appears when it does.
struct SwitchSection: View {
    let model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: capsAwakeBinding(model)) {
                HStack {
                    Text("capsawake_toggle")
                    Spacer()
                    // The key that does the same thing. It cannot be a real key
                    // equivalent — Caps Lock is only ever a modifier — so it is a
                    // hint next to the switch, and the footer spells it out.
                    Text(verbatim: "⇪")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        } header: {
            Text("settings_section_capsawake")
        } footer: {
            Text("capsawake_toggle_help")
                .foregroundStyle(.secondary)
        }
    }
}
