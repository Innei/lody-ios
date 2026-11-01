import AppKit

enum MacAccent: String, CaseIterable, Sendable {
  case lody, system, blue, purple, orange, graphite

  static let key = "lody.mac.accent"

  static func current(_ defaults: UserDefaults = .standard) -> MacAccent {
    defaults.string(forKey: key).flatMap(MacAccent.init(rawValue:)) ?? .lody
  }

  var color: NSColor {
    switch self {
    case .lody: .lodySignal
    case .system: .controlAccentColor
    case .blue: .systemBlue
    case .purple: .systemPurple
    case .orange: .systemOrange
    case .graphite: .systemGray
    }
  }

  var foregroundColor: NSColor {
    if self == .lody { return .lodySignalOnAccent }
    guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
    func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    return luminance > 0.179 ? .black : .white
  }

  var label: String {
    switch self {
    case .lody: "Lody"
    case .system: String(localized: "mac.accent.system", bundle: .lodyMac)
    case .blue: String(localized: "mac.accent.blue", bundle: .lodyMac)
    case .purple: String(localized: "mac.accent.purple", bundle: .lodyMac)
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
  // Same semantic palette as Shared/UIKit/Styling/LodyDesign.swift.
  private static func lodyColor(_ name: String, light: UInt32, dark: UInt32, lightHigh: UInt32, darkHigh: UInt32) -> NSColor {
    NSColor(name: NSColor.Name(name)) { appearance in
      let match = appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
      let rgb: UInt32
      switch match {
      case .accessibilityHighContrastDarkAqua: rgb = darkHigh
      case .accessibilityHighContrastAqua: rgb = lightHigh
      case .darkAqua: rgb = dark
      default: rgb = light
      }
      return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
  }
  static let lodySignal = lodyColor("lodySignal", light: 0x3550D4, dark: 0x8195FF, lightHigh: 0x2A40B0, darkHigh: 0xA3B2FF)
  static let lodySignalOnAccent = lodyColor("lodySignalOnAccent", light: 0xFFFFFF, dark: 0x0C0F24, lightHigh: 0xFFFFFF, darkHigh: 0x000000)
  static let lodyAccentForeground = NSColor(name: "lodyAccentForeground") { appearance in
    var result = NSColor.white
    appearance.performAsCurrentDrawingAppearance { result = MacAccent.current().foregroundColor.usingColorSpace(.sRGB) ?? .white }
    return result
  }
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
