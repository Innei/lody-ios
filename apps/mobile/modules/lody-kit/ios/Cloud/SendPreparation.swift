import Foundation

/// Removed synchronously before entering a runtime write; late callbacks cannot own its replacement.
@MainActor final class SendPreparation {
  private struct Attempt {
    let id: String
    let token: UUID
    let generation: Int
    let onCancel: (String) -> Void
    var task: Task<Void, Never>?
  }
  private var attempts: [String: Attempt] = [:]
  var count: Int { attempts.count }

  func begin(session: String, id: String, generation: Int, onCancel: @escaping (String) -> Void) -> UUID? {
    guard attempts[session] == nil else { return nil }
    let token = UUID()
    attempts[session] = Attempt(id: id, token: token, generation: generation, onCancel: onCancel)
    return token
  }

  func attach(_ task: Task<Void, Never>, session: String, token: UUID, generation: Int) {
    guard owns(session: session, token: token, generation: generation) else { task.cancel(); return }
    attempts[session]?.task = task
  }

  func owns(session: String, token: UUID, generation: Int) -> Bool {
    attempts[session]?.token == token && attempts[session]?.generation == generation
  }

  @discardableResult func finish(session: String, token: UUID, generation: Int) -> Bool {
    guard owns(session: session, token: token, generation: generation) else { return false }
    attempts.removeValue(forKey: session)
    return true
  }

  func cancel(session: String, id: String, generation: Int, reason: String) -> Bool {
    guard !id.isEmpty, let attempt = attempts[session], attempt.id == id,
      attempt.generation == generation else { return false }
    attempts.removeValue(forKey: session)
    attempt.task?.cancel()
    attempt.onCancel(reason)
    return true
  }

  func cancelAll(reason: String) {
    let pending = Array(attempts.values)
    attempts.removeAll()
    for attempt in pending {
      attempt.task?.cancel()
      attempt.onCancel(reason)
    }
  }
}
