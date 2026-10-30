import AppKit

enum MacTheme: String, CaseIterable, Sendable {
  case system, light, dark

  static let key = "lody.mac.theme"

  static func current(_ defaults: UserDefaults = .standard) -> MacTheme {
    defaults.string(forKey: key).flatMap(MacTheme.init(rawValue:)) ?? .system
  }

  var appearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  var label: String {
    switch self {
    case .system: String(localized: "mac.settings.theme.system", bundle: .lodyMac)
    case .light: String(localized: "mac.settings.theme.light", bundle: .lodyMac)
    case .dark: String(localized: "mac.settings.theme.dark", bundle: .lodyMac)
    }
  }

  func save(_ defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.key)
  }

  @MainActor
  func apply(_ defaults: UserDefaults = .standard) {
    save(defaults)
    NSApp.appearance = appearance
  }
}
