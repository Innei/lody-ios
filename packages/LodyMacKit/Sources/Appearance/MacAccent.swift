import AppKit

enum MacAccent: String, CaseIterable, Sendable {
  case system, blue, purple, pink, orange, graphite

  static let key = "lody.mac.accent"

  static func current(_ defaults: UserDefaults = .standard) -> MacAccent {
    defaults.string(forKey: key).flatMap(MacAccent.init(rawValue:)) ?? .system
  }

  var color: NSColor {
    switch self {
    case .system: .controlAccentColor
    case .blue: .systemBlue
    case .purple: .systemPurple
    case .pink: .systemPink
    case .orange: .systemOrange
    case .graphite: .systemGray
    }
  }

  var label: String {
    switch self {
    case .system: String(localized: "mac.accent.system", bundle: .lodyMac)
    case .blue: String(localized: "mac.accent.blue", bundle: .lodyMac)
    case .purple: String(localized: "mac.accent.purple", bundle: .lodyMac)
    case .pink: String(localized: "mac.accent.pink", bundle: .lodyMac)
    case .orange: String(localized: "mac.accent.orange", bundle: .lodyMac)
    case .graphite: String(localized: "mac.accent.graphite", bundle: .lodyMac)
    }
  }

  func save(_ defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.key)
  }

  @MainActor
  func apply() {
    save()
    for window in NSApp.windows { window.contentView.map(Self.redraw) }
    NotificationCenter.default.post(name: .lodyMacAccentDidChange, object: nil)
  }

  @MainActor
  private static func redraw(_ view: NSView) {
    view.needsDisplay = true
    view.subviews.forEach(redraw)
  }
}

extension NSColor {
  static let lodyAccent = NSColor(name: "lodyAccent") { appearance in
    var resolved = NSColor.controlAccentColor
    appearance.performAsCurrentDrawingAppearance {
      resolved = MacAccent.current().color.usingColorSpace(.sRGB) ?? .controlAccentColor
    }
    return resolved
  }
}

extension Notification.Name {
  static let lodyMacAccentDidChange = Notification.Name("lodyMacAccentDidChange")
}
