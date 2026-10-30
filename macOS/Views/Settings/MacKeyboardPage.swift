import AppKit
import SwiftUI

struct MacKeyboardPage: View {
  let groups: [MacShortcutList.Group]

  var body: some View {
    Form {
      Section {
        Text(String(localized: "mac.settings.shortcuts.detail", bundle: .lodyMac))
          .foregroundStyle(.secondary)
      }
      ForEach(groups) { group in
        Section(group.title) {
          ForEach(group.rows) { row in
            LabeledContent(row.title) {
              Text(row.keys).monospaced().foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .accessibilityIdentifier("settings-keyboard-list")
  }
}
