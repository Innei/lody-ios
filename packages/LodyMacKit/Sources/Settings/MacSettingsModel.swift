import AppKit
import LodyData
import Observation

@MainActor
struct MacSettingsServices {
  var source: SettingsSource
  var selectWorkspace: @MainActor (String) -> Void
  var signIn: @MainActor () -> Void
  var general: MacGeneralServices = .live
  var appearance: MacAppearanceServices = .live
  var machines: MacMachineServices = .live

  static var live: MacSettingsServices {
    MacSettingsServices(
      source: .live,
      selectWorkspace: { CatalogSession.shared.selectWorkspace($0) },
      signIn: { (NSApp.delegate as? LodyMacAppDelegate)?.showMain() }
    )
  }
}

@MainActor
@Observable
final class MacSettingsModel {
  struct Group: Identifiable {
    let section: MacSettingsPage.Section
    let pages: [MacSettingsPage]
    var id: MacSettingsPage.Section { section }
  }

  @ObservationIgnored let services: MacSettingsServices
  @ObservationIgnored let defaults: UserDefaults
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  private(set) var state: SettingsState
  @ObservationIgnored lazy var general = MacGeneralModel(services: services.general)
  @ObservationIgnored lazy var appearance = MacAppearanceModel(services: services.appearance)
  @ObservationIgnored lazy var machines = MacMachineList(services: services.machines)
  var query = ""
  var confirmingSignOut = false
  var page: MacSettingsPage

  init(services: MacSettingsServices, defaults: UserDefaults = .standard) {
    self.services = services
    self.defaults = defaults
    state = services.source.state
    page = MacSettingsPage.restored(defaults)
    observers = services.source.changes.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  var selection: MacSettingsPage? {
    get { page }
    set {
      guard let newValue else { return }
      page = newValue
      MacSettingsPage.remember(newValue, defaults)
    }
  }

  var signedIn: Bool { state.account != nil }
  var workspaces: [AuthWorkspace] { state.account?.workspaces ?? [] }
  var showsSwitcher: Bool { workspaces.count > 1 }

  var shownPage: MacSettingsPage {
    !signedIn && MacSettingsPage.Section.workspace.pages.contains(page) ? .account : page
  }

  var sections: [Group] {
    let matches = Set(MacSettingsPage.matching(query))
    return MacSettingsPage.Section.allCases.compactMap { section in
      guard signedIn || section != .workspace else { return nil }
      let pages = section.pages.filter(matches.contains)
      return pages.isEmpty ? nil : Group(section: section, pages: pages)
    }
  }

  func selectWorkspace(_ id: String) {
    services.selectWorkspace(id)
  }

  func signIn() {
    services.signIn()
  }

  func requestSignOut() {
    confirmingSignOut = true
  }

  func cancelSignOut() {
    confirmingSignOut = false
  }

  func confirmSignOut() async {
    confirmingSignOut = false
    await services.source.logout()
  }

  func refresh() {
    state = services.source.state
    machines.refreshPresence()
  }
}
