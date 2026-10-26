import Foundation

// UI verification fixtures that still live in React own their state; native pages ask them to
// apply a change and wait for the reply, so the fixture stays the only source of truth.
@MainActor
enum LodyPreviewBridge {
  private static var pending: [String: CheckedContinuation<Void, Error>] = [:]

  static var active: Bool { LodyUIVerify.enabled && SessionCatalogPreview.state != nil }

  static func request(_ action: String, _ fields: [String: Any], timeout: Duration = .seconds(10)) async throws {
    guard active, let emit = LodyShell.shared.emitNav else { throw failure("preview_unavailable") }
    let id = UUID().uuidString
    try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      emit(["type": "preview", "id": id, "action": action, "fields": fields])
      Task {
        try? await Task.sleep(for: timeout)
        settle(id, .failure(failure("preview_timeout")))
      }
    }
  }

  static func reply(_ id: String, error: String) {
    settle(id, error.isEmpty ? .success(()) : .failure(failure(error)))
  }

  // A torn-down fixture can never answer; a late reply then finds nothing to settle.
  static func reset() {
    let waiting = pending
    pending = [:]
    for continuation in waiting.values { continuation.resume(throwing: failure("preview_reset")) }
  }

  private static func settle(_ id: String, _ result: Result<Void, Error>) {
    pending.removeValue(forKey: id)?.resume(with: result)
  }

  private static func failure(_ code: String) -> NSError {
    NSError(domain: "LodyKit.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: code])
  }
}
