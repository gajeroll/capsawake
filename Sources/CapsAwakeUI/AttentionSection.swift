import CapsAwakeCore
import SwiftUI

/// What is stopping CapsAwake from working, at the top of the window where it cannot
/// be scrolled past.
///
/// The same items the menu warns about and the same order, because they come from the
/// same list. This says what is wrong and offers the one action that fixes it; the
/// Permissions section further down is the complete picture, wrong or not.
struct AttentionSection: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(model.pendingAccess) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Label {
                            Text(item.headlineKey)
                        } icon: {
                            Image(systemName: item.symbolName)
                                .foregroundStyle(item.tint)
                        }
                        Spacer()
                        Button {
                            model.resolve(item)
                        } label: {
                            Text(item.actionKey)
                        }
                    }
                    if let impactKey = item.impactKey {
                        Text(impactKey)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("settings_section_attention")
        } footer: {
            Text("settings_section_attention_help")
                .foregroundStyle(.secondary)
        }
    }
}
