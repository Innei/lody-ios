struct MacDraftHandoff {
  private var pending: String?

  mutating func sent(_ text: String) { pending = text }

  mutating func clear() { pending = nil }

  mutating func restore(current: String) -> String? {
    defer { pending = nil }
    guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return pending
  }
}
