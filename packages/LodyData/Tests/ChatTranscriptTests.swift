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

  func testSubagentsOfARunningProcessKnowTheirParentIsLive() {
    let duration = ChatRow(id: "t:duration", entryID: "t", kind: "duration", text: "", running: true)
    let task = ChatRow(id: "t:task", entryID: "t", kind: "subagent_task", text: "")
    let rows = ChatTranscript.hangSubagents([duration, task])
    XCTAssertEqual(rows.first { $0.kind == "subagent_task" }?.parentLive, true)
    let settled = ChatTranscript.hangSubagents([ChatRow(id: "t:duration", entryID: "t", kind: "duration", text: ""), task])
    XCTAssertEqual(settled.first { $0.kind == "subagent_task" }?.parentLive, false)
  }

  private let twoTurns = """
  [{"id":"u1","role":"user","status":"done","finished":true,"timestamp":"2026-10-30T02:40:00Z","items":[{"itemId":"q1","type":"text","text":"first"}]},
  {"id":"a1","role":"assistant","status":"done","finished":true,"items":[{"itemId":"r1","type":"text","text":"one"}]},
  {"id":"u2","role":"user","status":"done","finished":true,"timestamp":"2026-10-30T02:46:00Z","items":[{"itemId":"q2","type":"text","text":"second"}]},
  {"id":"a2","role":"assistant","status":"done","finished":true,"items":[{"itemId":"r2","type":"text","text":"two"}]}]
  """

  func testADividerSeparatesTurnsButNotTheFirst() throws {
    let rows = try transcript(twoTurns).rows()
    let turns = rows.filter { $0.kind == "turn" }
    XCTAssertEqual(turns.map(\.id), ["u2:turn"])
    let index = try XCTUnwrap(rows.firstIndex { $0.kind == "turn" })
    XCTAssertEqual(rows[index + 1].id, "u2:user")
    XCTAssertFalse(turns[0].text.isEmpty)
  }

  func testSteersInsideARunGetNoDivider() throws {
    let steered = twoTurns.replacingOccurrences(of: #""id":"u2","role":"user","status":"done""#, with: #""id":"u2","role":"user","status":"done","delivery":"accepted""#)
    XCTAssertTrue(try transcript(steered).rows().allSatisfy { $0.kind != "turn" })
  }

  func testTurnLabelsShowTimeTodayAndNameYesterday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_793_330_000).timeIntervalSince1970 * 1000
    let today = now - 60_000
    let todayLabel = ChatTranscript.turnLabel(today, now: now, calendar: calendar)
    XCTAssertEqual(todayLabel, Date(timeIntervalSince1970: today / 1000).formatted(date: .omitted, time: .shortened))
    let yesterday = now - 86_400_000
    let yesterdayLabel = ChatTranscript.turnLabel(yesterday, now: now, calendar: calendar)
    XCTAssertTrue(yesterdayLabel.contains(Date(timeIntervalSince1970: yesterday / 1000).formatted(date: .omitted, time: .shortened)))
    XCTAssertNotEqual(yesterdayLabel, Date(timeIntervalSince1970: yesterday / 1000).formatted(date: .omitted, time: .shortened))
    let older = now - 5 * 86_400_000
    XCTAssertEqual(ChatTranscript.turnLabel(older, now: now, calendar: calendar),
                   Date(timeIntervalSince1970: older / 1000).formatted(date: .abbreviated, time: .shortened))
  }

  func testAPendingSendOpensItsTurnWithADivider() throws {
    let entries = try JSONDecoder().decode([ChatEntry].self, from: Data(twoTurns.utf8))
    let pending = ChatPendingSend(id: "u3", text: "third", attachments: [], status: "")
    let rows = pending.rows(entries: entries)
    XCTAssertEqual(rows.first?.kind, "turn")
    XCTAssertEqual(rows.first?.id, "u3:turn")
    var guide = pending
    guide.guide = true
    XCTAssertTrue(guide.rows(entries: entries).allSatisfy { $0.kind != "turn" })
  }

  private func changed(_ files: [String]) -> String {
    let diffs = files.map { #"{"path":"\#($0)","add":3,"del":1}"# }.joined(separator: ",")
    return """
    [{"id":"a","role":"assistant","status":"done","finished":true,"modelInfo":{"title":"Codex"},"fileDiffs":[\(diffs)],
    "items":[{"itemId":"r","type":"text","text":"done"}]}]
    """
  }

  func testTheFileBlockComesBeforeTheMetaRow() throws {
    let kinds = try transcript(changed(["a.swift", "b.swift"])).rows().map(\.kind)
    let header = try XCTUnwrap(kinds.firstIndex(of: "changesHeader"))
    let meta = try XCTUnwrap(kinds.firstIndex(of: "meta"))
    XCTAssertLessThan(header, meta)
    XCTAssertLessThan(try XCTUnwrap(kinds.lastIndex(of: "changes")), meta)
  }

  func testASingleChangedFileIsOneRowWithoutASummary() throws {
    let rows = try transcript(changed(["only.swift"])).rows()
    XCTAssertFalse(rows.contains { $0.kind == "changesHeader" })
    let file = try XCTUnwrap(rows.first { $0.kind == "changes" })
    XCTAssertEqual(file.group, "only")
  }

  func testAPendingStatusSitsBelowItsTurnDivider() throws {
    let entries = try JSONDecoder().decode([ChatEntry].self, from: Data(twoTurns.utf8))
    let pending = ChatPendingSend(id: "u3", text: "third", attachments: [], status: "Sending")
    let merged = ChatPendingSend.merging(pending.rows(entries: entries), into: try transcript(twoTurns).rows())
    let tail = merged.filter { $0.entryID == "u3" }.map(\.kind)
    XCTAssertEqual(tail, ["turn", "delivery", "user"])
  }

  func testAnExitingStatusReturnsBelowTheDivider() throws {
    let rows = try transcript(twoTurns).rows()
    let index = try XCTUnwrap(ChatPendingSend.deliveryIndex(in: rows, entryID: "u2"))
    XCTAssertEqual(rows[index].id, "u2:user")
  }

  func testSessionPreviewsLeaveOutTurnDividers() {
    XCTAssertTrue(ChatTranscript.previewRows(from: twoTurns).allSatisfy { $0.kind != "turn" })
  }
}
