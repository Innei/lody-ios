import XCTest
@testable import LodyMacKit

@MainActor
final class MacVerifyInboxTests: XCTestCase {
  func testMessagesCarryASequenceAndRoutesInOrder() {
    let message = MacVerifyInbox.parse("7 lodymacverify://reset lodymacverify://appearance/dark lodymacverify://case/sidebar")
    XCTAssertEqual(message?.seq, "7")
    XCTAssertEqual(message?.routes, [.reset, .appearance("dark"), .scene("sidebar")])
  }

  func testMalformedMessagesAreIgnored() {
    XCTAssertNil(MacVerifyInbox.parse(""))
    XCTAssertNil(MacVerifyInbox.parse("lodymacverify://case/sidebar"))
    XCTAssertNil(MacVerifyInbox.parse("7 lodymacverify://case/../etc"))
    XCTAssertNil(MacVerifyInbox.parse("7 lody://case/sidebar"))
  }

  func testHandlingAppliesEveryRouteBeforeAcknowledging() {
    var events: [String] = []
    let inbox = MacVerifyInbox(route: { events.append("route \($0)") }, acknowledge: { events.append("ack \($0)") })
    inbox.handle("3 lodymacverify://appearance/light lodymacverify://case/settings")
    inbox.handle("4 lody://case/settings")
    XCTAssertEqual(events, ["route appearance(\"light\")", "route scene(\"settings\")", "ack 3"])
  }

  func testTheInboxListensOnTheDistributedCenter() {
    let received = expectation(description: "route delivered")
    var acknowledged: [String] = []
    let inbox = MacVerifyInbox(route: { _ in received.fulfill() }, acknowledge: { acknowledged.append($0) })
    inbox.listen()
    DistributedNotificationCenter.default().postNotificationName(
      MacVerifyInbox.request, object: "9 lodymacverify://reset", userInfo: nil, deliverImmediately: true
    )
    wait(for: [received], timeout: 5)
    XCTAssertEqual(acknowledged, ["9"])
    inbox.stop()
  }
}
