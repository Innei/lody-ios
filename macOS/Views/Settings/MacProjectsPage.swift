import LodyData
import SwiftUI

struct MacProjectsPage: View {
  let settings: MacSettingsModel
  @Bindable var model: MacProjectsModel

  var body: some View {
    Form {
      if model.failed {
        Section { Text(String(localized: "mac.settings.failed", bundle: .lodyMac)).foregroundStyle(.secondary) }
      } else if model.loading && model.groups.isEmpty {
        Section { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
      } else if model.groups.isEmpty {
        Section { Text(String(localized: "mac.settings.projects.empty", bundle: .lodyMac)).foregroundStyle(.secondary) }
      }
      ForEach(model.groups) { group in
        Section {
          ForEach(group.rows) { row in
            MacProjectLine(row: row, saving: model.saving.contains(row.id)) { shared in
              guard let workspace = settings.state.workspace?.id else { return }
              Task { await model.setShared(row, shared, workspaceId: workspace) }
            }
          }
        } header: {
          HStack {
            Text(group.name)
            Spacer()
            MacPresenceText(status: group.status)
          }
        }
      }
      if !model.groups.isEmpty {
        Section {} footer: {
          Text(String(localized: "mac.settings.projects.footer", bundle: .lodyMac)).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .task(id: settings.state.workspace?.id) {
      guard let workspace = settings.state.workspace?.id else { return }
      await model.load(workspaceId: workspace)
    }
    .onReceive(NotificationCenter.default.publisher(for: .lodyCatalogDidChange)) { _ in model.refreshCatalog() }
    .alert(String(localized: "mac.settings.failed", bundle: .lodyMac), isPresented: $model.shareFailed) {
      Button(String(localized: "mac.settings.ok", bundle: .lodyMac), role: .cancel) {}
    }
  }
}

struct MacProjectLine: View {
  let row: MacProjectRow
  let saving: Bool
  let share: (Bool) -> Void

  var body: some View {
    let label = Label {
      Text(row.name)
      Text(row.path).font(.caption.monospaced())
    } icon: {
      Image(systemName: "folder")
    }
    if row.owned, let shared = row.shared {
      Toggle(isOn: Binding(get: { shared }, set: share)) { label }
        .disabled(saving)
        .help(String(localized: "mac.settings.projects.share", bundle: .lodyMac))
        .accessibilityIdentifier("settings-projects-share-\(row.id)")
    } else {
      LabeledContent {
        if let shared = row.shared {
          Text(String(localized: shared ? "mac.settings.projects.shared" : "mac.settings.projects.private", bundle: .lodyMac))
            .foregroundStyle(.secondary)
        }
      } label: {
        label
      }
    }
  }
}
