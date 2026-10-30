import QuickLook
import UIKit

@MainActor
enum FilePreviewCoordinator {
  static func read(sessionId: String, path: String, runtime: DataRuntime) async throws -> String {
    let payload = String(
      data: try JSONSerialization.data(withJSONObject: ["sessionId": sessionId, "path": path]),
      encoding: .utf8
    )!
    if let failure = FilePreviewFixture.failure(payload) {
      throw failure
    }
    if let response = FilePreviewFixture.response(payload) {
      let fast = ["document.pdf", "interactive.html", "broken.html", "preview.css", "preview.js"].contains { payload.contains($0) }
      let delay = fast ? 0.0 : 5.0
      if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
      try Task.checkCancellation()
      return response
    }
    return try await runtime.readFile(payload)
  }

  static func presentsQuickLook(_ path: String) -> Bool {
    switch ChatFileLink.iconName(for: path) {
    case "image", "pdf", "video", "audio", "zip", "word", "powerpoint", "table":
      return true
    default:
      return false
    }
  }

  static func open(
    sessionId: String,
    path: String,
    line: Int,
    runtime: DataRuntime,
    from controller: UIViewController
  ) async -> Bool {
    guard !sessionId.isEmpty, !path.isEmpty else { return false }
    if presentsQuickLook(path) {
      await FileQuickLookController.present(
        sessionId: sessionId, path: path, runtime: runtime, from: controller
      )
      return true
    }
    return false
  }
}
