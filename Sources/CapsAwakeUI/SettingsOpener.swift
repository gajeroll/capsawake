import SwiftUI

/// Hands SwiftUI's `openSettings` action to non-SwiftUI code.
///
/// The action is only reachable from a view's environment, and the app delegate
/// needs it to open Settings when the app is reopened from Finder.
public struct SettingsOpener: View {
    private let register: (@escaping () -> Void) -> Void

    public init(register: @escaping (@escaping () -> Void) -> Void) {
        self.register = register
    }

    @Environment(\.openSettings) private var openSettings

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                let action = openSettings
                register { action() }
            }
    }
}
