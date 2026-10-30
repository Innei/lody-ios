import AppKit

enum MacSettingsPage: String, CaseIterable, Identifiable {
  case account, general, appearance, keyboard, workspace, machines, projects, about
  #if DEBUG
  case debug
  #endif

  static let key = "lody.mac.settings.page"

  var id: String { rawValue }

  enum Section: CaseIterable {
    case personal, workspace, other

    var title: String {
      switch self {
      case .personal: String(localized: "mac.settings.section.personal", bundle: .lodyMac)
      case .workspace: String(localized: "mac.settings.section.workspace", bundle: .lodyMac)
      case .other: String(localized: "mac.settings.section.other", bundle: .lodyMac)
      }
    }

    var pages: [MacSettingsPage] {
      switch self {
      case .personal: [.general, .appearance, .keyboard]
      case .workspace: [.workspace, .machines, .projects]
      case .other: MacSettingsPage.otherPages
      }
    }
  }

  private static var otherPages: [MacSettingsPage] {
    #if DEBUG
    [.about, .debug]
    #else
    [.about]
    #endif
  }

  var title: String {
    String(localized: String.LocalizationValue("mac.settings.page.\(rawValue)"), bundle: .lodyMac)
  }

  var symbol: String {
    switch self {
    case .account: "person.crop.circle"
    case .general: "gearshape"
    case .appearance: "circle.lefthalf.filled"
    case .keyboard: "keyboard"
    case .workspace: "building.2"
    case .machines: "desktopcomputer"
    case .projects: "folder"
    case .about: "info.circle"
    #if DEBUG
    case .debug: "hammer"
    #endif
    }
  }

  var tile: NSColor {
    switch self {
    case .appearance: NSColor(white: 0.12, alpha: 1)
    case .workspace: .systemBlue
    case .machines: .systemIndigo
    case .projects: .systemOrange
    default: .systemGray
    }
  }

  var keywords: [String] {
    let keys: [String] = switch self {
    case .account: ["mac.settings.myMachines", "mac.settings.signOut", "mac.settings.signIn"]
    case .general: [
      "mac.settings.section.conversations", "mac.settings.queue.title", "mac.settings.queue.queue", "mac.settings.queue.steer",
      "mac.settings.desktopNotifications", "mac.settings.notifications", "mac.settings.login",
    ]
    case .appearance: ["mac.settings.theme", "mac.settings.accent", "mac.settings.textSize", "mac.settings.fillWidth"]
    case .keyboard: ["mac.settings.shortcuts"]
    case .workspace: ["mac.settings.workspace.name", "mac.settings.workspace.icon", "mac.settings.workspace.members"]
    case .machines: ["mac.settings.machines.rename"]
    case .projects: ["mac.settings.projects.share"]
    case .about: ["mac.settings.version", "mac.settings.licenses", "mac.settings.diagnostics"]
    #if DEBUG
    case .debug: []
    #endif
    }
    return keys.map { String(localized: String.LocalizationValue($0), bundle: .lodyMac) }
  }

  static func matching(_ query: String) -> [MacSettingsPage] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return allCases }
    return allCases.filter { page in
      ([page.title] + page.keywords).contains { $0.localizedCaseInsensitiveContains(needle) }
    }
  }

  static func restored(_ defaults: UserDefaults = .standard) -> MacSettingsPage {
    defaults.string(forKey: key).flatMap(MacSettingsPage.init(rawValue:)) ?? .general
  }

  static func remember(_ page: MacSettingsPage, _ defaults: UserDefaults = .standard) {
    defaults.set(page.rawValue, forKey: key)
  }
}
