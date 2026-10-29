import XCTest
@testable import LodyData

final class ChatTranscriptTests: XCTestCase {
  private let reply = """
  [{"id":"reply","role":"assistant","status":"running","finished":true,"items":[
  {"itemId":"intro","type":"thought","text":"check"},
  {"itemId":"tool","type":"tool_call","title":"Read file","status":"completed"},
  {"itemId":"answer","type":"text","text":"done"}]}]
  """

  private func transcript(_ json: String) throws -> ChatTranscript {
    ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(json.utf8)))
  }

  func testToolCallsFoldIntoAProcessSummary() throws {
    let rows = try transcript(reply).rows()
    XCTAssertTrue(rows.contains { $0.kind == "summary" && $0.actionable })
    XCTAssertFalse(rows.contains { $0.itemID == "tool" })
    XCTAssertTrue(rows.contains { $0.itemID == "answer" })
    XCTAssertEqual(try transcript(reply).rows(processEntryID: "reply").map(\.itemID), ["intro", "tool"])
  }

  func testFailedToolsRaiseAttentionWithAWarningMark() throws {
    let rows = try transcript(reply.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"status\":\"failed\"")).rows()
    let summary = try XCTUnwrap(rows.first { $0.kind == "summary" })
    XCTAssertTrue(summary.attention)
    XCTAssertEqual(summary.symbol, "exclamationmark.triangle.fill")
  }

  func testPendingPermissionMakesTheToolActionable() throws {
    let json = reply.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"permission\":{\"requestId\":\"p\",\"pending\":true}")
    let process = try transcript(json).rows(processEntryID: "reply")
    XCTAssertTrue(process.contains { $0.itemID == "tool" && $0.actionable && $0.attention })
  }
}
