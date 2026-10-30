import AppKit
import ChatAppKit
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

  func testALongHistoryOpensOnTheLatestPageAndPagesEarlierTurnsInFromTheTop() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = transcript
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<1000).map { .user(id: "u\($0)", text: "Message \($0)") }
    transcript.render(model)
    window.layoutIfNeeded()
    XCTAssertFalse(texts(in: transcript).contains("Message 900"))
    scrollToTop(transcript)
    XCTAssertEqual(transcript.descendants(CKHistoryHeaderView.self).first?.labels.more, String(localized: "mac.transcript.history.more", bundle: .lodyMac))
    XCTAssertTrue(texts(in: transcript).contains("Message 950"))
    let paged = expectation(description: "earlier page")
    Task { @MainActor in
      while !texts(in: transcript).contains("Message 900") {
        scrollToTop(transcript)
        try? await Task.sleep(for: .milliseconds(20))
      }
      paged.fulfill()
    }
    wait(for: [paged], timeout: 5)
  }

  func testASentTurnLandsAtTheTopOfTheTranscript() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = transcript
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<3).map { .user(id: "u\($0)", text: "Message \($0)") }
    transcript.render(model)
    window.layoutIfNeeded()
    transcript.noteSend()
    model.items.append(.user(id: "sent", text: "Ship it"))
    transcript.render(model)
    let landed = expectation(description: "landed")
    Task { @MainActor in
      while abs(self.top(of: "Ship it", in: transcript) - 7) > 1 { try? await Task.sleep(for: .milliseconds(20)) }
      landed.fulfill()
    }
    wait(for: [landed], timeout: 3)
  }

  private func top(of text: String, in transcript: MacTranscriptView) -> CGFloat {
    guard let scroll = transcript.descendants(NSScrollView.self).first,
          let label = transcript.rowViews.flatMap({ $0.descendants(NSTextField.self) }).first(where: { $0.stringValue == text }),
          let row = label.enclosingCellContent
    else { return .greatestFiniteMagnitude }
    return row.convert(row.bounds, to: scroll.contentView).minY - scroll.contentView.bounds.minY
  }

  private func scrollToTop(_ transcript: MacTranscriptView) {
    guard let scroll = transcript.descendants(NSScrollView.self).first else { return }
    NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
    scroll.reflectScrolledClipView(scroll.contentView)
    NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    transcript.layoutSubtreeIfNeeded()
  }

  private func texts(in transcript: MacTranscriptView) -> [String] {
    transcript.rowViews.flatMap { $0.descendants(NSTextField.self) }.map(\.stringValue)
  }
}

private extension NSView {
  var enclosingCellContent: NSView? {
    var view: NSView? = self
    while let current = view, !(current.superview is NSTableCellView) { view = current.superview }
    return view
  }
}
