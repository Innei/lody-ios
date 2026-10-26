import Foundation

// UI verification fixtures that still live in React own their state; native pages ask them to
// apply a change and wait for the reply, so the fixture stays the only source of truth.
@MainActor
enum LodyPreviewBridge {
  static var active: Bool { LodyUIVerify.enabled && SessionCatalogPreview.state != nil }

  static func request(_ action: String, _ fields: [String: Any], timeout: Duration = .seconds(10)) async throws {
    guard active else { throw LodyNavRequest.failure("preview_unavailable") }
    try await LodyNavRequest.send(
      ["type": "preview", "action": action, "fields": fields], key: "preview:\(UUID().uuidString)", timeout: timeout,
      via: LodyShell.shared.emitNav
    )
  }

  static func reset() { LodyNavRequest.reset(prefix: "preview:") }
}
