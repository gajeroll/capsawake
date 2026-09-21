import CapsAwakeCore
import SwiftUI

/// Everything that depends on what Caps Lock has been made into: the grant itself, the
/// capitals switch it brings into being, the combination that reaches the same switch
/// from the keyboard, and the delay in front of the key.
struct CapsLockSection: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.dedicatedMode) private var dedicatedMode = false
    @AppStorage(UserPreferenceKey.removeCapsLockDelay) private var removeCapsLockDelay = true
    @AppStorage(UserPreferenceKey.shiftTypesSmallLetters)
    private var shiftTypesSmallLetters = false

    var body: some View {
        Section {
            DedicatedModeToggle()
            // Capitals are separable from sleep prevention only while the filter is
            // running, so this row exists only while the row above it is on.
            if dedicatedMode {
                CapitalsToggle(model: model)
            }
            CapitalsShortcutRow(model: model)
            // The Windows habit, offered where capitals exist to have a habit about.
            if dedicatedMode {
                Toggle(isOn: $shiftTypesSmallLetters) {
                    Text("shift_types_small_letters")
                }
            }
            Toggle(isOn: $removeCapsLockDelay) {
                Text("remove_caps_lock_delay")
            }
        } header: {
            Text("settings_section_caps_lock")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("dedicated_mode_help")
                CapitalsShortcutHelp(model: model)
                if dedicatedMode {
                    Text("shift_types_small_letters_help")
                }
                Text("remove_caps_lock_delay_help")
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// The modifiers that, held with Caps Lock, switch capitals instead of CapsAwake.
///
/// The combination is set by pressing it: the app is watching the keyboard anyway,
/// so asking for the keys themselves is both shorter than describing them and the
/// only way to be sure the keys the user has are the keys that arrive. The button
/// shows the combination in force, and clearing it leaves no combination at all —
/// the switch above is then the only way to reach capitals.
struct CapitalsShortcutRow: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.capitalsModifiers) private var stored = CapsLockModifiers.shift
        .rawValue

    var body: some View {
        let modifiers = CapsLockModifiers(rawValue: stored)
        HStack {
            Text("capitals_shortcut")
            Spacer()
            Button {
                model.onRecordCapitalsShortcut?(!model.isRecordingCapitalsShortcut)
            } label: {
                // Fixed width: the label changes as the user records, and a button
                // that resized under the pointer would be the wrong one to click.
                title(for: modifiers)
                    .fixedSize()
                    .frame(minWidth: 120)
            }
            // Glyphs alone leave the button unlabelled for assistive tech, so the
            // row's own name is the label and the combination is its value.
            .accessibilityLabel(Text("capitals_shortcut"))
            .accessibilityValue(title(for: modifiers))
            .accessibilityHint(Text("capitals_shortcut_record_hint"))
            Button {
                model.onRecordCapitalsShortcut?(false)
                stored = CapsLockModifiers().rawValue
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(modifiers.isEmpty)
            .accessibilityLabel(Text("capitals_shortcut_clear"))
        }
    }

    private func title(for modifiers: CapsLockModifiers) -> Text {
        if model.isRecordingCapitalsShortcut {
            Text("capitals_shortcut_listening")
        } else if modifiers.isEmpty {
            Text("capitals_shortcut_none")
        } else {
            Text(verbatim: modifiers.shortcutSymbols)
        }
    }
}

/// Spells out what the chosen combination does, because the button above shows the
/// keys but not which of the two switches they reach.
struct CapitalsShortcutHelp: View {
    let model: AppModel

    @AppStorage(UserPreferenceKey.capitalsModifiers) private var stored = CapsLockModifiers.shift
        .rawValue

    var body: some View {
        let modifiers = CapsLockModifiers(rawValue: stored)
        if model.isRecordingCapitalsShortcut {
            Text("capitals_shortcut_listening_help")
        } else if modifiers.isEmpty {
            Text("capitals_shortcut_none_help")
        } else {
            Text("capitals_shortcut_set_help \(modifiers.shortcutSymbols)")
        }
    }
}
