import AppKit
import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacTranscriptTableTests: XCTestCase {
  func testAThousandItemTranscriptBuildsOnlyTheVisibleRows() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = transcript
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<1000).map { .user(id: "u\($0)", text: "Message \($0)") }
    transcript.render(model)
    window.layoutIfNeeded()
    XCTAssertLessThan(transcript.rowViews.count, 60)
    XCTAssertTrue(transcript.isScrolledToBottom)
  }

  func testThePermissionCardIsTheLastRow() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = transcript
    let json = """
    [{"id":"a1","role":"assistant","items":[{"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit file","permission":{"pending":true,"requestId":"r1","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"}]}}]}]
    """
    let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    let permission = try XCTUnwrap(SessionPermission.first(in: entries))
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = [.user(id: "u", text: "Hi")]
    transcript.render(model, card: .init(permission: permission, options: permission.options ?? [], busy: false, error: ""))
    window.layoutIfNeeded()
    XCTAssertEqual(transcript.descendants(MacPermissionCard.self).count, 1)
    transcript.render(model, card: nil)
    window.layoutIfNeeded()
    XCTAssertTrue(transcript.descendants(MacPermissionCard.self).isEmpty)
  }
}
