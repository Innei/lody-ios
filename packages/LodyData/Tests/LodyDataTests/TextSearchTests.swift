import XCTest
import LodyData

final class TextSearchTests: XCTestCase {
  func testRangesIgnoreCaseAndDiacritics() {
    let ranges = TextSearch.ranges(in: "Café and CAFE", query: "cafe")
    XCTAssertEqual(ranges, [NSRange(location: 0, length: 4), NSRange(location: 9, length: 4)])
  }

  func testBlankQueryMatchesNothing() {
    XCTAssertEqual(TextSearch.ranges(in: "anything", query: "  "), [])
  }

  func testPlainTextDropsMarkdownDecoration() {
    XCTAssertEqual(MarkdownPlainText.string("**Bold** and [link](https://example.com)"), "Bold and link")
  }
}
