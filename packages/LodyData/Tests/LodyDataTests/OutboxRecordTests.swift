import XCTest
import LodyCore
import LodyData

final class OutboxRecordTests: XCTestCase {
  private func record(_ phase: String) -> OutboxRecord {
    OutboxRecord(
      session: ["id": .string("session")],
      send: ["id": .string("send"), "phase": .string(phase), "text": .string("ping"), "attachments": .array([]),
             "choice": .object(["modelId": .string("model")])])
  }

  func testInFlightSendsRestoreAsUnconfirmedInsteadOfReplaying() {
    let raw = OutboxRecord.encode([record("sending"), record("failed")])
    let restored = OutboxRecord.restore(raw, awaitingConfirmation: "Awaiting confirmation")
    XCTAssertEqual(restored.map(\.phase), ["unknown", "failed"])
    XCTAssertEqual(restored.first?.send["reason"], .string("Awaiting confirmation"))
  }

  func testIncompleteRecordsAreDropped() {
    var broken = record("queued")
    broken.send["text"] = nil
    XCTAssertEqual(OutboxRecord.restore(OutboxRecord.encode([broken]), awaitingConfirmation: ""), [])
  }
}
