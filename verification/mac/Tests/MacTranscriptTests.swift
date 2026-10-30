import XCTest
@testable import LodyMacApp

final class MacTranscriptTests: XCTestCase {
  private let entries = """
  [{"id":"u1","role":"user","status":"completed","finished":true,"items":[{"itemId":"q","type":"text","text":"Add a Mac sidebar"}]},
   {"id":"a1","role":"assistant","status":"completed","finished":true,"items":[
    {"itemId":"think","type":"thought","text":"Checking the shell"},
    {"itemId":"read","type":"tool_call","kind":"read","title":"Read MainWindowController.swift","status":"completed"},
    {"itemId":"plan","type":"proposed_plan","markdown":"# Plan\\n1. Sidebar","status":"completed","isLatest":true},
    {"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit SidebarViewController.swift","permission":{"pending":true,"requestId":"r1","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},{"optionId":"deny","name":"Deny","kind":"reject_once"}]}},
    {"itemId":"answer","type":"text","text":"The sidebar is in place."}]}]
  """

  func testToolCallsBecomeQuietActivityLinesAndPlansStayDocuments() {
    let model = MacTranscriptModel(entriesJSON: entries)
    guard case .user(_, let question)? = model.items.first else { return XCTFail("\(model.items)") }
    XCTAssertEqual(question, "Add a Mac sidebar")
    let activity = model.items.compactMap { item -> String? in
      if case .activity(_, _, let text, _, _) = item { return text }
      return nil
    }
    XCTAssertTrue(activity.contains("Read MainWindowController.swift"), "\(activity)")
    XCTAssertTrue(model.items.contains { if case .plan(_, let markdown) = $0 { markdown.contains("1. Sidebar") } else { false } })
    XCTAssertTrue(model.items.contains { if case .prose(_, let markdown) = $0 { markdown == "The sidebar is in place." } else { false } })
  }

  func testPendingPermissionBecomesTheOnlyCard() throws {
    let model = MacTranscriptModel(entriesJSON: entries)
    let permission = try XCTUnwrap(model.permission)
    XCTAssertEqual(permission.requestId, "r1")
    XCTAssertEqual(permission.options?.map(\.name), ["Allow", "Deny"])
    XCTAssertTrue(model.items.contains { if case .activity(_, _, let text, true, _) = $0 { text.contains("SidebarViewController") } else { false } })
  }

  func testMalformedEntriesRenderNothing() {
    XCTAssertTrue(MacTranscriptModel(entriesJSON: "not json").items.isEmpty)
    XCTAssertNil(MacTranscriptModel(entriesJSON: "[]").permission)
  }

  func testNarrationInsideAFinishedTurnStaysProse() {
    let finished = """
    [{"id":"u1","role":"user","status":"completed","finished":true,"items":[{"itemId":"q","type":"text","text":"Add a sidebar"}]},
     {"id":"a1","role":"assistant","status":"completed","finished":true,"items":[
      {"itemId":"read","type":"tool_call","kind":"read","title":"Read MainWindowController.swift","status":"completed"},
      {"itemId":"intro","type":"text","text":"I'll add an outline view."},
      {"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit SidebarViewController.swift","status":"completed"},
      {"itemId":"done","type":"text","text":"The sidebar is in place."}]}]
    """
    let prose = MacTranscriptModel(entriesJSON: finished).items.compactMap { item -> String? in
      if case .prose(_, let markdown) = item { return markdown }
      return nil
    }
    XCTAssertEqual(prose, ["I'll add an outline view.", "The sidebar is in place."])
  }

  @MainActor
  func testProseReadsAsPlainTextToVoiceOver() {
    let view = MacMarkdownView(markdown: "I'll add an `NSOutlineView`:\n\n- **Pinned** first")
    XCTAssertTrue(view.isAccessibilityElement())
    XCTAssertEqual(view.accessibilityRole(), .staticText)
    XCTAssertEqual(view.accessibilityValue() as? String, "I'll add an NSOutlineView:\n\n- Pinned first")
    view.update("Approved. **Pinned** stays on top.")
    XCTAssertEqual(view.accessibilityValue() as? String, "Approved. Pinned stays on top.")
  }
}
