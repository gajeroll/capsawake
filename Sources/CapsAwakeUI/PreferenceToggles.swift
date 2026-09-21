import CapsAwakeCore
import SwiftUI

/// The switches that appear in both the menu and the Settings window, so the
/// wording and the polarity are decided in one place.

/// Turns CapsAwake on and off.
///
/// The Caps Lock LED is the real switch, so this reports what the app is doing and
/// hands the write to the controller instead of storing it.
@MainActor
func capsAwakeBinding(_ model: AppModel) -> Binding<Bool> {
    Binding(
        get: { model.isActive },
        set: { _ in model.onToggleRequested?() }
    )
}

struct CapsAwakeToggle: View {
    let model: AppModel

    var body: some View {
        Toggle(isOn: capsAwakeBinding(model)) {
            Text("capsawake_toggle")
        }
    }
}

/// Whether the keyboard is locked to capitals right now.
///
/// The capitals combination by another route, not a preference: it reports the state
/// the status icon draws its fill from and asks the app to change it, so pressing the
/// combination moves this switch and moving this switch is the same as pressing the
/// combination.
///
/// Shown only while Caps Lock is CapsAwake's, because capitals are separable from
/// sleep prevention only then; the plain lock does both at once, and a switch for it
/// here would have been the sleep prevention switch under a second name.
///
/// It used to write the preference behind the combination instead — whether Caps Lock
/// belongs to CapsAwake — which is a different question and has a switch of its own in
/// Settings. Turning it on therefore only handed the key back rather than locking
/// anything to capitals, and nothing happened until Caps Lock was pressed.
struct CapitalsToggle: View {
    let model: AppModel

    var body: some View {
        Toggle(isOn: capitalsBinding(model)) {
            Text("all_caps_typing")
        }
    }
}

@MainActor
func capitalsBinding(_ model: AppModel) -> Binding<Bool> {
    Binding(
        get: { model.capitalsLocked },
        set: { model.onSetCapitalsLocked?($0) }
    )
}

/// Whether Caps Lock is CapsAwake's alone.
///
/// The one preference behind the capitals switch: with it on, the event filter takes
/// Caps Lock out of key events, which is what leaves capitals free to be switched on
/// their own and what needs Accessibility. With it off the key is a plain Caps Lock as
/// well, so capitals and sleep prevention are one switch and only that one is shown.
struct DedicatedModeToggle: View {
    @AppStorage(UserPreferenceKey.dedicatedMode) private var dedicatedMode = false

    var body: some View {
        Toggle(isOn: $dedicatedMode) {
            Text("dedicated_mode")
        }
    }
}
