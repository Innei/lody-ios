import LodyData
import SwiftUI

struct MacAccountPage: View {
  @Bindable var model: MacSettingsModel

  var body: some View {
    Form {
      Section {
        VStack(spacing: 6) {
          MacSettingsAvatar(user: model.state.account?.user, size: 72)
          if let user = model.state.account?.user {
            Text(user.name.isEmpty ? user.email : user.name).font(.title2.weight(.semibold))
            Text(user.email).foregroundStyle(.secondary)
          } else {
            Button(String(localized: "mac.settings.signIn", bundle: .lodyMac)) { model.signIn() }
              .controlSize(.large)
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("settings-account-signIn")
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }
      if model.signedIn {
        Section(String(localized: "mac.settings.myMachines", bundle: .lodyMac)) {
          MacOwnedMachines(list: model.machines)
        }
        Section {
          Button(String(localized: "mac.settings.signOut", bundle: .lodyMac), role: .destructive) { model.requestSignOut() }
            .foregroundStyle(.red)
            .accessibilityIdentifier("settings-account-signOut")
        }
      }
    }
    .formStyle(.grouped)
    .task(id: model.state.workspace?.id) {
      guard let workspace = model.state.workspace?.id else { return }
      await model.machines.load(workspaceId: workspace)
    }
    .alert(String(localized: "mac.settings.signOut.confirm", bundle: .lodyMac), isPresented: $model.confirmingSignOut) {
      Button(String(localized: "mac.settings.signOut", bundle: .lodyMac), role: .destructive) {
        Task { await model.confirmSignOut() }
      }
      Button(String(localized: "mac.settings.cancel", bundle: .lodyMac), role: .cancel) { model.cancelSignOut() }
    } message: {
      Text(String(localized: "mac.settings.signOut.detail", bundle: .lodyMac))
    }
  }
}

struct MacOwnedMachines: View {
  let list: MacMachineList

  var body: some View {
    if (list.loading || list.waiting) && list.owned.isEmpty {
      ProgressView().controlSize(.small).frame(maxWidth: .infinity)
    } else if list.failed {
      Text(String(localized: "mac.settings.failed", bundle: .lodyMac)).foregroundStyle(.secondary)
    } else if list.owned.isEmpty {
      Text(String(localized: "mac.settings.machines.empty", bundle: .lodyMac)).foregroundStyle(.secondary)
    } else {
      ForEach(list.owned) { MacMachineLabel(row: $0) }
    }
  }
}

struct MacMachineLabel: View {
  let row: MacMachineRow

  var body: some View {
    LabeledContent {
      MacPresenceText(status: row.status)
    } label: {
      Label {
        Text(row.name)
        if let detail = row.machine.detail, !detail.isEmpty { Text(detail) }
      } icon: {
        Image(systemName: "desktopcomputer")
      }
    }
    .accessibilityIdentifier("settings-machine-\(row.id)")
  }
}

struct MacPresenceText: View {
  let status: String

  var body: some View {
    switch status {
    case "online":
      Label(String(localized: "mac.settings.online", bundle: .lodyMac), systemImage: "circle.fill")
        .labelStyle(MacPresenceLabelStyle(color: .green))
    case "offline":
      Label(String(localized: "mac.settings.offline", bundle: .lodyMac), systemImage: "circle.fill")
        .labelStyle(MacPresenceLabelStyle(color: .secondary))
    default:
      EmptyView()
    }
  }
}

private struct MacPresenceLabelStyle: LabelStyle {
  let color: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon.font(.system(size: 6)).foregroundStyle(color)
      configuration.title.foregroundStyle(.secondary)
    }
  }
}
