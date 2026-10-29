import XCTest
@testable import LodyData

@MainActor
final class SessionSenderTests: XCTestCase {
  private func services() -> OutboxServices {
    OutboxServices(
      createSession: { _ in "" },
      ensureSession: { _ in },
      sendSessionTurn: { _ in "" },
      releaseReserve: { _ in },
      alert: { _, _ in }
    )
  }

  func testSubmitWithoutAReadyOutboxHandsTheDraftBack() {
    let sender = SessionSender(sessionId: "s1", store: nil, services: services(), inflight: OutboxInflight())
    var restored: [Int] = []
    sender.restoreDraft = { restored.append($0) }
    sender.update(.init(userId: "u1", connected: true))
    XCTAssertFalse(sender.canSend)
    sender.submit(["text": "hi"], choice: [:])
    XCTAssertEqual(restored, [1])
    XCTAssertEqual(sender.pendingSendJSON, "")
  }

  func testUploadProgressReadsNotificationPayload() {
    let event = SessionUploadProgress(["sessionId": "s1", "sendId": "x", "attachmentId": "a", "phase": "uploading", "percent": NSNumber(value: 40)])
    XCTAssertEqual(event.percent, 40)
    XCTAssertEqual(event.phase, "uploading")
  }
}
