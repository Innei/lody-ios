import Foundation

public struct QuickReply: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let message: String

  public init(id: String, label: String, message: String) {
    self.id = id
    self.label = label
    self.message = message
  }
}

extension QuickReply {
  public init?(_ value: Any?) {
    guard let value = value as? [String: Any], let id = value["id"] as? String,
          let label = value["label"] as? String, let message = value["message"] as? String else { return nil }
    self.init(id: id, label: label, message: message)
  }
}

public struct PreferencesSnapshot: Codable, Equatable, Sendable {
  public let accentColor: String
  public let darkBackground: String
  public let queuedMessageBehavior: String
  public let quickReplies: [QuickReply]

  public init(accentColor: String, darkBackground: String, queuedMessageBehavior: String, quickReplies: [QuickReply]) {
    self.accentColor = accentColor
    self.darkBackground = darkBackground
    self.queuedMessageBehavior = queuedMessageBehavior
    self.quickReplies = quickReplies
  }
}

public enum LodyPreferences: Sendable {
  private static let queuedKey = "queuedMessageBehavior"
  private static let quickRepliesKey = "quickReplies"
  private static let defaultReplyIDs = ["continue", "review", "commit-push"]

  public static var snapshot: PreferencesSnapshot {
    PreferencesSnapshot(
      accentColor: LodyAccentChoice.current.rawValue,
      darkBackground: LodyDarkBackground.current.rawValue,
      queuedMessageBehavior: queuedMessageBehavior,
      quickReplies: quickReplies
    )
  }

  public static var json: String {
    (try? JSONEncoder().encode(snapshot)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }

  public static var queuedMessageBehavior: String {
    UserDefaults.standard.string(forKey: queuedKey) == "guide" ? "guide" : "queue"
  }

  public static func saveQueuedMessageBehavior(_ value: String) {
    let next = value == "guide" ? "guide" : "queue"
    guard next != queuedMessageBehavior else { return }
    UserDefaults.standard.set(next, forKey: queuedKey)
    changed()
  }

  public static var quickReplies: [QuickReply] {
    guard let json = UserDefaults.standard.string(forKey: quickRepliesKey),
          let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { return defaultQuickReplies }
    return valid(items)
  }

  public static func saveQuickReplies(_ items: [QuickReply]) -> Bool {
    guard let data = try? JSONEncoder().encode(valid(items)) else { return false }
    UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: quickRepliesKey)
    changed()
    return true
  }

  public static func resetQuickReplies() {
    UserDefaults.standard.removeObject(forKey: quickRepliesKey)
    changed()
  }

  public static var defaultQuickReplies: [QuickReply] {
    defaultReplyIDs.map { id in
      QuickReply(
        id: id,
        label: String(localized: String.LocalizationValue("settings.quickReplies.defaults." + id + ".label"), bundle: .lodyData),
        message: String(localized: String.LocalizationValue("settings.quickReplies.defaults." + id + ".message"), bundle: .lodyData)
      )
    }
  }

  private static func valid(_ items: [Any]) -> [QuickReply] {
    valid(items.compactMap { QuickReply($0) })
  }

  // Limits count UTF-16 units to match the editor's maxLength.
  private static func valid(_ items: [QuickReply]) -> [QuickReply] {
    var ids = Set<String>()
    return items.filter { item in
      let blank = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      guard !item.id.isEmpty, !ids.contains(item.id), !blank(item.label), item.label.utf16.count <= 40,
            !blank(item.message), item.message.utf16.count <= 32000 else { return false }
      ids.insert(item.id)
      return true
    }
  }

  private static func changed() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .lodyPreferencesDidChange, object: nil)
    }
  }
}

extension Notification.Name {
  public static let lodyPreferencesDidChange = Notification.Name("LodyPreferencesDidChange")
}
