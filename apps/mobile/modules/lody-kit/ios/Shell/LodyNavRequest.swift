import Foundation

// Native asks React for something it still owns and waits for the reply. Transitional: callbacks
// exist only while session navigation lives in React (delete with the native sessionNav).
@MainActor
enum LodyNavRequest {
  private struct Pending {
    let key: String
    let continuation: CheckedContinuation<Void, Error>
  }

  private static var pending: [String: Pending] = [:]

  static func send(_ event: [String: Any], key: String, timeout: Duration?, via emit: (([String: Any]) -> Void)?) async throws {
    guard let emit else { throw failure("nav_unavailable") }
    guard !pending.values.contains(where: { $0.key == key }) else { throw failure("request_in_flight") }
    let id = UUID().uuidString
    try await withCheckedThrowingContinuation { continuation in
      pending[id] = Pending(key: key, continuation: continuation)
      emit(event.merging(["id": id]) { _, new in new })
      guard let timeout else { return }
      Task {
        try? await Task.sleep(for: timeout)
        settle(id, .failure(failure("request_timeout")))
      }
    }
  }

  static func busy(_ key: String) -> Bool { pending.values.contains { $0.key == key } }

  static func reply(_ id: String, error: String) {
    settle(id, error.isEmpty ? .success(()) : .failure(failure(error)))
  }

  // An owner that went away can never answer; a late reply then finds nothing to settle.
  static func reset(prefix: String) {
    for (id, request) in pending where request.key.hasPrefix(prefix) {
      settle(id, .failure(failure("request_reset")))
    }
  }

  private static func settle(_ id: String, _ result: Result<Void, Error>) {
    pending.removeValue(forKey: id)?.continuation.resume(with: result)
  }

  static func failure(_ code: String) -> NSError {
    NSError(domain: "LodyKit.Nav", code: 1, userInfo: [NSLocalizedDescriptionKey: code])
  }
}
