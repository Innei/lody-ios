import XCTest

final class TranscriptHistoryTests: LodyMacUITestCase {
  func testScrollingToTheTopPagesInEarlierHistory() {
    open("transcript-history", "light")
    let table = scene.tables["transcript"]
    XCTAssertTrue(scene.staticTexts["Read MainWindowController.swift"].waitForExistence(timeout: 5))
    XCTAssertFalse(scene.staticTexts["Earlier turn 952"].exists, "only the latest page opens")
    eventually("scrolling up reaches the latest page's first turn", timeout: 15) {
      table.scroll(byDeltaX: 0, deltaY: 1500)
      return scene.staticTexts["Earlier turn 952"].exists
    }
    eventually("the earlier page loads above it", timeout: 15) {
      table.scroll(byDeltaX: 0, deltaY: 1500)
      return scene.staticTexts["Earlier turn 902"].exists
    }
    attach("transcript-history-paged", scene)
  }

  func testATenThousandEntryTranscriptOpensAndScrolls() {
    let started = Date()
    open("transcript-history-10k", "light")
    XCTAssertTrue(scene.staticTexts["Read MainWindowController.swift"].waitForExistence(timeout: 15))
    let opened = Date().timeIntervalSince(started)
    let table = scene.tables["transcript"]
    let scrolling = Date()
    for _ in 0..<20 { table.scroll(byDeltaX: 0, deltaY: 400) }
    let scrolled = Date().timeIntervalSince(scrolling)
    let numbers = XCTAttachment(string: String(format: "open %.2f s, 20 scroll steps %.2f s", opened, scrolled))
    numbers.name = "transcript-10k-perf"
    numbers.lifetime = .keepAlways
    add(numbers)
    attach("transcript-10k-scrolled", scene)
    XCTAssertLessThan(opened, 10, "a 10,000-entry session opens")
  }
}
