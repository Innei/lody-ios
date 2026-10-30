import LodyData
import SwiftUI

struct MacSettingsView: View {
  @Bindable var model: MacSettingsModel

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selection) {
        MacSettingsAccountCard(state: model.state)
          .tag(MacSettingsPage.account)
          .accessibilityIdentifier("settings-account")
        ForEach(model.sections) { group in
          Section {
            ForEach(group.pages) { page in
              Label {
                Text(page.title)
              } icon: {
                MacSettingsTile(page: page)
              }
              .tag(page)
              .accessibilityIdentifier("settings-\(page.rawValue)")
            }
          } header: {
            MacSettingsSectionHeader(section: group.section, model: model)
          }
        }
      }
      .listStyle(.sidebar)
      .tint(Color(nsColor: .systemGray))
      .searchable(text: $model.query, placement: .sidebar, prompt: Text(String(localized: "mac.settings.search", bundle: .lodyMac)))
      .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    } detail: {
      MacSettingsDetail(model: model)
        .navigationTitle(model.shownPage.title)
    }
  }
}

struct MacSettingsTile: View {
  let page: MacSettingsPage

  var body: some View {
    Image(systemName: page.symbol)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: page.tile)))
      .accessibilityHidden(true)
  }
}

struct MacSettingsAvatar: View {
  let user: AuthUser?
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle().fill(Color(nsColor: .systemGray))
      Text(initials)
        .font(.system(size: size * 0.38, weight: .semibold))
        .foregroundStyle(.white)
      if let image = user?.image.flatMap(URL.init(string:)) {
        AsyncImage(url: image) { phase in
          phase.image?.resizable().scaledToFill()
        }
        .clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var initials: String {
    let name = user?.name.isEmpty == false ? user?.name : user?.email
    return String((name ?? "?").prefix(2)).uppercased()
  }
}

struct MacSettingsAccountCard: View {
  let state: SettingsState

  var body: some View {
    HStack(spacing: 10) {
      MacSettingsAvatar(user: state.account?.user, size: 36)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).fontWeight(.semibold).lineLimit(1)
        Text(String(localized: "mac.settings.accountCard", bundle: .lodyMac))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var title: String {
    guard let user = state.account?.user else { return String(localized: "mac.settings.signIn", bundle: .lodyMac) }
    return user.name.isEmpty ? user.email : user.name
  }
}

struct MacSettingsSectionHeader: View {
  let section: MacSettingsPage.Section
  let model: MacSettingsModel

  var body: some View {
    HStack {
      Text(section.title)
      Spacer()
      if section == .workspace, model.showsSwitcher {
        Menu {
          ForEach(model.workspaces, id: \.id) { workspace in
            Button(workspace.name) { model.selectWorkspace(workspace.id) }
          }
        } label: {
          Text(model.state.workspace?.name ?? "")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(String(localized: "mac.settings.workspace.switch", bundle: .lodyMac))
        .accessibilityIdentifier("settings-workspace-switch")
      }
    }
  }
}

struct MacSettingsDetail: View {
  let model: MacSettingsModel

  var body: some View {
    switch model.shownPage {
    case .general:
      MacGeneralPage(model: model.general)
    case .account:
      MacAccountPage(model: model)
    case .workspace:
      MacWorkspacePage(settings: model, model: model.workspace)
    case .appearance:
      MacAppearancePage(model: model.appearance)
    case .keyboard:
      MacKeyboardPage(groups: NSApp.mainMenu.map { MacShortcutList.groups(from: $0) } ?? [])
    #if DEBUG
    case .debug:
      MacSettingsDebugPage()
    #endif
    default:
      Form {}
        .formStyle(.grouped)
    }
  }
}

#if DEBUG
struct MacSettingsDebugPage: NSViewControllerRepresentable {
  func makeNSViewController(context: Context) -> MacDebugController { MacDebugController() }
  func updateNSViewController(_ controller: MacDebugController, context: Context) {}
}
#endif
