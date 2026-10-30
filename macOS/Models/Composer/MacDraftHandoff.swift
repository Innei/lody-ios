struct MacDraftHandoff {
  private var pending: (text: String, attachments: [MacDraftAttachment])?

  mutating func sent(_ text: String, attachments: [MacDraftAttachment] = []) { pending = (text, attachments) }

  mutating func clear() { pending = nil }

  mutating func restore(current: String) -> String? {
    restore(current: current, hasAttachments: false)?.text
  }

  mutating func restore(current: String, hasAttachments: Bool) -> (text: String, attachments: [MacDraftAttachment])? {
    defer { pending = nil }
    guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !hasAttachments else { return nil }
    return pending
  }
}
