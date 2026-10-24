import Foundation

struct QuickReply: Codable, Equatable, Sendable {
  let id: String
  let label: String
  let message: String
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

  static func saveQuickReplies(json: String) -> Bool {
    guard let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any],
          let data = try? JSONEncoder().encode(valid(items)) else { return false }
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

  // Limits count UTF-16 units to match the editor's maxLength.
  private static func valid(_ items: [Any]) -> [QuickReply] {
    var ids = Set<String>()
    return items.compactMap { item in
      guard let item = item as? [String: Any],
            let id = item["id"] as? String, !id.isEmpty, !ids.contains(id),
            let label = item["label"] as? String, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            label.utf16.count <= 40,
            let message = item["message"] as? String, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            message.utf16.count <= 32000 else { return nil }
      ids.insert(id)
      return QuickReply(id: id, label: label, message: message)
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
