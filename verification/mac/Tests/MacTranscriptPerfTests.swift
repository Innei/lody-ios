import AppKit
import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacTranscriptPerfTests: XCTestCase {
  func testATenThousandEntryTranscriptOpensAndScrollsWithinBudget() throws {
    var json = ""
    MacTranscriptFixture(history: 10000).source.start { json = $0.entriesJSON }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
    window.contentView = transcript

    let opening = Date()
    let model = MacTranscriptModel(entriesJSON: json)
    let projected = Date().timeIntervalSince(opening)
    transcript.render(model)
    window.layoutIfNeeded()
    transcript.layoutSubtreeIfNeeded()
    let opened = Date().timeIntervalSince(opening)

    let scroll = try XCTUnwrap(transcript.descendants(NSScrollView.self).first)
    let scrolling = Date()
    NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    for _ in 0..<40 {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.contentView.bounds.minY - 120)))
      scroll.reflectScrolledClipView(scroll.contentView)
      transcript.layoutSubtreeIfNeeded()
    }
    NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    let scrolled = Date().timeIntervalSince(scrolling)

    print(String(format: "PERF transcript-10k model %.0f ms, open %.0f ms, 40 scroll steps %.0f ms, %d rows built", projected * 1000, opened * 1000, scrolled * 1000, transcript.rowViews.count))
    XCTAssertEqual(model.items.count, 10006)
    XCTAssertLessThan(transcript.rowViews.count, 80)
    XCTAssertLessThan(opened, 3)
    XCTAssertLessThan(scrolled / 40, 1.0 / 30)
  }
}
