import Foundation

public enum LodyDarkBackground: String {
  case soft
  case black

  public static var current: Self {
    Self(rawValue: UserDefaults.standard.string(forKey: "darkBackground") ?? "") ?? .soft
  }

  public static func save(_ value: String) {
    let next = Self(rawValue: value) ?? .soft
    guard next != current else { return }
    UserDefaults.standard.set(next.rawValue, forKey: "darkBackground")
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .lodyAppearanceDidChange, object: nil)
    }
  }
}

public enum LodyAccentChoice: Equatable, RawRepresentable {
  case ink, blue, indigo, purple, pink
  case custom(String)

  public init?(rawValue: String) {
    switch rawValue {
    case "ink": self = .ink
    case "blue": self = .blue
    case "indigo": self = .indigo
    case "purple": self = .purple
    case "pink": self = .pink
    default:
      guard rawValue.utf8.count == 7, rawValue.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { return nil }
      self = .custom(rawValue.uppercased())
    }
  }

  public var rawValue: String {
    switch self {
    case .ink: "ink"
    case .blue: "blue"
    case .indigo: "indigo"
    case .purple: "purple"
    case .pink: "pink"
    case .custom(let hex): hex
    }
  }

  // The Share Extension has its own standard defaults; the app mirrors the accent here.
  public static var shared: UserDefaults? { UserDefaults(suiteName: "group.app.innei.lody") }

  public static var current: Self {
    #if LODY_SHARE_EXTENSION
    let defaults = shared ?? .standard
    #else
    let defaults = UserDefaults.standard
    #endif
    return Self(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .ink
  }

  public static func mirror() {
    shared?.set(current.rawValue, forKey: "accentColor")
  }

  public static func store(_ value: String) -> Bool {
    guard let next = Self(rawValue: value), next != current else { return false }
    UserDefaults.standard.set(next.rawValue, forKey: "accentColor")
    mirror()
    return true
  }
}

extension Notification.Name {
  public static let lodyAppearanceDidChange = Notification.Name("LodyAppearanceDidChange")
}
