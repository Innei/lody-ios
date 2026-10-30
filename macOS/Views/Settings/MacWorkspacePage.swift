import AppKit
import LodyData
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct MacWorkspacePage: View {
  let settings: MacSettingsModel
  let model: MacWorkspaceModel
  @State private var name = ""

  var body: some View {
    Form {
      if let workspace = settings.state.workspace {
        Section {
          LabeledContent(String(localized: "mac.settings.workspace.icon", bundle: .lodyMac)) {
            HStack(spacing: 10) {
              MacWorkspaceIcon(workspace: workspace, size: 40)
              if model.canEdit {
                Button(String(localized: "mac.settings.workspace.chooseIcon", bundle: .lodyMac)) {
                  Task { await model.chooseIcon(workspace.id) }
                }
                .accessibilityIdentifier("settings-workspace-icon")
              }
            }
          }
          if model.canEdit {
            TextField(String(localized: "mac.settings.workspace.name", bundle: .lodyMac), text: $name)
              .onSubmit { Task { await model.rename(workspace.id, to: name) } }
              .accessibilityIdentifier("settings-workspace-name")
          } else {
            LabeledContent(String(localized: "mac.settings.workspace.name", bundle: .lodyMac), value: workspace.name)
          }
        } footer: {
          if let error = model.error {
            Text(error).foregroundStyle(.red)
          } else if !model.canEdit, !model.loading {
            Text(String(localized: "mac.settings.workspace.readOnly", bundle: .lodyMac)).foregroundStyle(.secondary)
          }
        }
        Section(String(localized: "mac.settings.workspace.members", bundle: .lodyMac)) {
          if model.failed {
            Text(String(localized: "mac.settings.failed", bundle: .lodyMac)).foregroundStyle(.secondary)
          } else if model.loading && model.members.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
          } else {
            ForEach(model.members) { member in
              MacMemberRow(member: member)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { name = settings.state.workspace?.name ?? "" }
    .onChange(of: settings.state.workspace?.name) { name = settings.state.workspace?.name ?? "" }
    .task(id: settings.state.workspace?.id) {
      guard let workspace = settings.state.workspace?.id else { return }
      await model.load(workspaceId: workspace)
    }
  }
}

struct MacWorkspaceIcon: View {
  let workspace: AuthWorkspace
  let size: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color(nsColor: .systemBlue))
      Text(String(workspace.name.prefix(1)).uppercased())
        .font(.system(size: size * 0.45, weight: .semibold))
        .foregroundStyle(.white)
      if let image = workspace.image.flatMap(URL.init(string:)) {
        AsyncImage(url: image) { $0.image?.resizable().scaledToFill() }
          .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct MacMemberRow: View {
  let member: WorkspaceMembers.Member

  var body: some View {
    LabeledContent {
      Text(MacMemberRow.role(member.role)).foregroundStyle(.secondary)
    } label: {
      HStack(spacing: 8) {
        MacSettingsAvatar(user: AuthUser(id: member.id, name: member.name, email: member.email, image: member.image), size: 24)
        VStack(alignment: .leading, spacing: 1) {
          Text(member.name.isEmpty ? member.email : member.name)
          if !member.name.isEmpty { Text(member.email).font(.caption).foregroundStyle(.secondary) }
        }
      }
    }
  }

  static func role(_ raw: String) -> String {
    let roles = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let top = ["owner", "admin", "member"].first(where: roles.contains) ?? roles.first ?? raw
    switch top {
    case "owner": return String(localized: "mac.settings.role.owner", bundle: .lodyMac)
    case "admin": return String(localized: "mac.settings.role.admin", bundle: .lodyMac)
    case "member": return String(localized: "mac.settings.role.member", bundle: .lodyMac)
    default: return top
    }
  }
}
