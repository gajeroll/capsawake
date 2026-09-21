import AppKit
import CapsAwakeCore
import SwiftUI

/// The status item image. Reads `model` inside a view body so Observation keeps
/// the icon in sync; a `Scene` body would not track it.
public struct MenuBarLabel: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Image(nsImage: MenuBarIcon.image(for: model.presentation))
            .renderingMode(.original)
            .accessibilityLabel(Text(accessibilityKey))
    }

    private var accessibilityKey: LocalizedStringKey {
        switch model.presentation {
        case .active(let capitals): capitals ? "tooltip_active_caps_typing" : "tooltip_active"
        case .capsLockTyping: "tooltip_caps_typing"
        case .idle: "tooltip_idle"
        case .error(.dedicatedPermission): "tooltip_dedicated_error"
        case .error(.daemonApproval): "tooltip_daemon_approval"
        case .error: "tooltip_privileged_error"
        }
    }
}

/// Builds the status item image.
///
/// Green matches the keyboard LED and so means sleep prevention, which is also why
/// those states cannot be template images. The fill means capitals. The two are read
/// separately, and neither rests on colour alone: green with no fill is sleep
/// prevention on its own, a fill with no green is capitals on their own.
enum MenuBarIcon {
    static func image(for presentation: StatusPresentation) -> NSImage {
        switch presentation {
        case .active(let capitals):
            tinted(capitals ? "capslock.fill" : "capslock", with: .systemGreen)
        case .capsLockTyping: template("capslock.fill")
        case .idle: template("capslock")
        case .error: template("exclamationmark.triangle.fill")
        }
    }

    private static func template(_ name: String) -> NSImage {
        let image = symbol(name)
        image.isTemplate = true
        return image
    }

    private static func tinted(_ name: String, with color: NSColor) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        guard let image = symbol(name).withSymbolConfiguration(configuration) else {
            return template(name)
        }
        image.isTemplate = false
        return image
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

/// The menu carries what belongs in reach at the moment it is opened: the switch,
/// the one option that changes how a key press behaves, and a way out. Everything
/// else lives in the Settings window.
///
/// The warning rows above them appear only when something is broken. They come
/// from the same list the icon reads, so a warning icon always has a row here.
public struct MenuBarContent: View {
    private let model: AppModel

    /// Capitals are a switch of their own only while Caps Lock is CapsAwake's.
    /// Until then they are the hardware lock, which the sleep prevention switch
    /// already follows, so a second row would move with the first and read as one
    /// switch drawn twice.
    @AppStorage(UserPreferenceKey.dedicatedMode) private var dedicatedMode = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        // Every permission the icon is warning about, not just the highest-ranked
        // one: a menu that explained one problem and stayed silent about the rest
        // read as "nothing is wrong" the moment the first was fixed.
        ForEach(model.pendingAccess) { item in
            Text(item.headlineKey)
            Button {
                model.resolve(item)
            } label: {
                Text(item.actionKey)
            }
            Divider()
        }

        if model.lidCloseWarning {
            Text("lid_close_may_sleep_warning")
            Divider()
        }

        CapsAwakeToggle(model: model)
        if dedicatedMode {
            CapitalsToggle(model: model)
        }

        Divider()

        // Not a `SettingsLink`: it opens the window without activating the app, so
        // the window lands behind whatever the user was working in.
        Button {
            model.onOpenSettings?()
        } label: {
            Text("open_settings")
        }
        Button {
            model.onRestart?()
        } label: {
            Text("restart")
        }

        Divider()

        Button {
            model.onQuit?()
        } label: {
            Text("quit")
        }
        .keyboardShortcut("q")
    }
}
