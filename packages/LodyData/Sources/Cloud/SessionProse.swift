import Foundation

public enum SessionProse: Sendable {
  public struct Item: Sendable {
    public let entryID: String
    public let itemID: String
    public let text: String

    public init(entryID: String, itemID: String, text: String) {
      self.entryID = entryID
      self.itemID = itemID
      self.text = text
    }
  }

  public static func text(_ source: String, role: String) -> String {
    let text = role == "user" ? source : MarkdownPlainText.string(source)
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
  }

  public static func extract(_ value: String) -> [Item] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
      object["v"] as? Int == 1, let entries = object["entries"] as? [[String: Any]] else { return [] }
    return entries.flatMap { entry -> [Item] in
      guard let id = entry["id"] as? String, let items = entry["items"] as? [[String: Any]] else { return [] }
      return items.compactMap { item in
        guard let type = item["type"] as? String, ["text", "thought", "proposed_plan"].contains(type),
          type != "proposed_plan" || ["delta", "completed"].contains(item["status"] as? String ?? ""),
          let itemID = item["itemId"] as? String, let source = item[type == "proposed_plan" ? "markdown" : "text"] as? String else { return nil }
        let body = text(source, role: entry["role"] as? String ?? "assistant")
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Item(entryID: id, itemID: itemID, text: body)
      }
    }
  }
}
