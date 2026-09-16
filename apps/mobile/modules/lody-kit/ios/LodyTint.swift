import UIKit

enum LodyDarkBackground: String {
  case soft
  case black

  static var current: Self {
    Self(rawValue: UserDefaults.standard.string(forKey: "darkBackground") ?? "") ?? .soft
  }

  static func save(_ value: String) {
    let next = Self(rawValue: value) ?? .soft
    guard next != current else { return }
    UserDefaults.standard.set(next.rawValue, forKey: "darkBackground")
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .lodyAppearanceDidChange, object: nil)
    }
  }
}

extension Notification.Name {
  static let lodyAppearanceDidChange = Notification.Name("LodyAppearanceDidChange")
}

func lodyTint(_ value: String) -> UIColor? {
  switch value {
  case "": return nil
  case "blue": return UIColor.lodyAccent
  case "green": return .systemGreen
  case "purple": return .systemPurple
  case "warning": return .systemOrange
  case "danger": return .systemRed
  case "yellow": return .systemYellow
  case "secondary": return .secondaryLabel
  case "tertiary": return .tertiaryLabel
  default: break
  }
  var hex = value
  if hex.hasPrefix("#") { hex.removeFirst() }
  guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
  return UIColor(
    red: CGFloat((rgb >> 16) & 0xFF) / 255,
    green: CGFloat((rgb >> 8) & 0xFF) / 255,
    blue: CGFloat(rgb & 0xFF) / 255,
    alpha: 1
  )
}

extension UIColor {
  static let lodyBackground = UIColor { traits in
    if traits.userInterfaceStyle != .dark {
      return UIColor.systemBackground.resolvedColor(with: traits)
    }
    return LodyDarkBackground.current == .soft
      ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1)
      : .black
  }

  static let lodyGroupedBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.lodyBackground.resolvedColor(with: traits)
      : UIColor.systemGroupedBackground.resolvedColor(with: traits)
  }

  /// Glass sheets resolve grouped semantics to vibrant fills. Rows that still
  /// need to read as cards use these opaque system card values instead.
  static let lodyOpaqueCard = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
      : .white
  }

  static let lodyAccent = UIColor { traits in
    if let named = UIColor(named: "AccentColor") {
      return named.resolvedColor(with: traits)
    }
    return traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x4A / 255, green: 0x88 / 255, blue: 0xFF / 255, alpha: 1)
      : UIColor(red: 0x21 / 255, green: 0x55 / 255, blue: 0xCC / 255, alpha: 1)
  }

  static let lodyUserBubble = UIColor { traits in
    let amount: CGFloat = traits.userInterfaceStyle == .dark ? 0.14 : 0.10
    return UIColor.lodyAccent.resolvedColor(with: traits).withAlphaComponent(amount)
  }

  /// Recessed chip on the reading canvas. Light is Tailwind `neutral-100`;
  /// dark matches `secondarySystemBackground` so file cards and code blocks
  /// sit on black without a mid-grey slab.
  static let lodyInset = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
      : UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, alpha: 1)
  }

  /// Resting inset and selected fill stay a pair so `selectItem` still reads.
  /// Light is Tailwind `neutral-200`; dark is `tertiarySystemBackground`.
  static let lodyInsetSelected = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
      : UIColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE5 / 255, alpha: 1)
  }

  static let lodyFileGroup = UIColor { traits in
    UIColor.lodyInset.resolvedColor(with: traits)
  }

  static let lodyFileGroupSelected = UIColor { traits in
    UIColor.lodyInsetSelected.resolvedColor(with: traits)
  }
}

@MainActor
func lodyApplyWindowAccent() {
  UIWindow.appearance().tintColor = .lodyAccent
  for scene in UIApplication.shared.connectedScenes {
    guard let scene = scene as? UIWindowScene else { continue }
    for window in scene.windows {
      window.tintColor = .lodyAccent
    }
  }
}
