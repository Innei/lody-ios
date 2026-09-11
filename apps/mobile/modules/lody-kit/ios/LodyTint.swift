import ExpoModulesCore
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

class LodyAppearanceView: ExpoView {
  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lodyAppearanceDidChange),
      name: .lodyAppearanceDidChange,
      object: nil
    )
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc func lodyAppearanceDidChange() {}
}

func lodyTint(_ value: String) -> UIColor? {
  switch value {
  case "": return nil
  case "blue": return .systemBlue
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
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x7B / 255, green: 0x8A / 255, blue: 0xFF / 255, alpha: 1)
      : UIColor(red: 0x3B / 255, green: 0x4F / 255, blue: 0xD9 / 255, alpha: 1)
  }

  /// Accent washed with the reading canvas so the user bubble stays tinted, not solid.
  static let lodyUserBubble = UIColor { traits in
    let amount: CGFloat = traits.userInterfaceStyle == .dark ? 0.14 : 0.10
    return UIColor.lodyAccent.mixed(with: .lodyBackground, amount: amount, traits: traits)
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

  func mixed(with other: UIColor, amount: CGFloat, traits: UITraitCollection) -> UIColor {
    let lhs = resolvedColor(with: traits)
    let rhs = other.resolvedColor(with: traits)
    var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
    var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
    lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
    rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
    let t = min(1, max(0, amount))
    return UIColor(
      red: lr * t + rr * (1 - t),
      green: lg * t + rg * (1 - t),
      blue: lb * t + rb * (1 - t),
      alpha: 1
    )
  }
}
