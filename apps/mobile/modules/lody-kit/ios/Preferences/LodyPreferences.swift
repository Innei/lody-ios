import Foundation

struct QuickReply: Codable, Equatable, Sendable {
  let id: String
  let label: String
  let message: String
}

extension QuickReply {
  init?(_ value: Any?) {
    guard let value = value as? [String: Any], let id = value["id"] as? String,
          let label = value["label"] as? String, let message = value["message"] as? String else { return nil }
    self.init(id: id, label: label, message: message)
  }
}

struct PreferencesSnapshot: Codable, Equatable, Sendable {
  let accentColor: String
  let darkBackground: String
  let queuedMessageBehavior: String
  let quickReplies: [QuickReply]
}

enum LodyPreferences {
  private static let queuedKey = "queuedMessageBehavior"
  private static let quickRepliesKey = "quickReplies"
  private static let defaultReplyIDs = ["continue", "review", "commit-push"]

  static var snapshot: PreferencesSnapshot {
    PreferencesSnapshot(
      accentColor: LodyAccentChoice.current.rawValue,
      darkBackground: LodyDarkBackground.current.rawValue,
      queuedMessageBehavior: queuedMessageBehavior,
      quickReplies: quickReplies
    )
  }

  static var json: String {
    (try? JSONEncoder().encode(snapshot)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }

  static var queuedMessageBehavior: String {
    UserDefaults.standard.string(forKey: queuedKey) == "guide" ? "guide" : "queue"
  }

  static func saveQueuedMessageBehavior(_ value: String) {
    let next = value == "guide" ? "guide" : "queue"
    guard next != queuedMessageBehavior else { return }
    UserDefaults.standard.set(next, forKey: queuedKey)
    changed()
  }

  static var quickReplies: [QuickReply] {
    guard let json = UserDefaults.standard.string(forKey: quickRepliesKey),
          let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { return defaultQuickReplies }
    return valid(items)
  }

  static func saveQuickReplies(_ items: [QuickReply]) -> Bool {
    guard let data = try? JSONEncoder().encode(valid(items)) else { return false }
    UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: quickRepliesKey)
    changed()
    return true
  }

  static func resetQuickReplies() {
    UserDefaults.standard.removeObject(forKey: quickRepliesKey)
    changed()
  }

  static var defaultQuickReplies: [QuickReply] {
    defaultReplyIDs.map { id in
      QuickReply(
        id: id,
        label: LodyStrings.text("settings.quickReplies.defaults.\(id).label"),
        message: LodyStrings.text("settings.quickReplies.defaults.\(id).message")
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
  static let lodyPreferencesDidChange = Notification.Name("LodyPreferencesDidChange")
}
