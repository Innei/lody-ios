import LodyData
import SwiftUI

struct MacMachinesPage: View {
  let settings: MacSettingsModel
  @Bindable var list: MacMachineList
  @State private var renaming: MacMachineRow?
  @State private var name = ""

  var body: some View {
    Form {
      Section {
        if list.failed {
          Text(String(localized: "mac.settings.failed", bundle: .lodyMac)).foregroundStyle(.secondary)
        } else if list.loading && list.rows.isEmpty {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if list.rows.isEmpty {
          Text(String(localized: "mac.settings.machines.empty", bundle: .lodyMac)).foregroundStyle(.secondary)
        } else {
          ForEach(list.rows) { row in
            HStack {
              MacMachineLabel(row: row)
              if row.canRename {
                Button(String(localized: "mac.settings.machines.rename", bundle: .lodyMac)) {
                  name = row.name
                  renaming = row
                }
                .controlSize(.small)
                .accessibilityIdentifier("settings-machines-rename-\(row.id)")
              } else {
                Image(systemName: "lock")
                  .foregroundStyle(.tertiary)
                  .help(String(localized: "mac.settings.machines.ownerOnly", bundle: .lodyMac))
                  .accessibilityLabel(String(localized: "mac.settings.machines.ownerOnly", bundle: .lodyMac))
              }
            }
          }
        }
      } header: {
        HStack {
          Spacer()
          Button {
            Task { await reload() }
          } label: {
            Label(String(localized: "mac.settings.machines.refresh", bundle: .lodyMac), systemImage: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .disabled(list.loading)
          .accessibilityIdentifier("settings-machines-refresh")
        }
      }
    }
    .formStyle(.grouped)
    .task(id: settings.state.workspace?.id) { await reload() }
    .alert(String(localized: "mac.settings.machines.rename", bundle: .lodyMac), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField(String(localized: "mac.settings.workspace.name", bundle: .lodyMac), text: $name)
      Button(String(localized: "mac.settings.save", bundle: .lodyMac)) {
        guard let row = renaming, let workspace = settings.state.workspace?.id else { return }
        Task { await list.rename(row, to: name, workspaceId: workspace) }
      }
      Button(String(localized: "mac.settings.cancel", bundle: .lodyMac), role: .cancel) {}
    }
    .alert(String(localized: "mac.settings.failed", bundle: .lodyMac), isPresented: $list.renameFailed) {
      Button(String(localized: "mac.settings.ok", bundle: .lodyMac), role: .cancel) {}
    }
  }

  private func reload() async {
    guard let workspace = settings.state.workspace?.id else { return }
    await list.load(workspaceId: workspace)
  }
}
