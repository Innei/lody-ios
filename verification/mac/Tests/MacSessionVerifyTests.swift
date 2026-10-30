import AppKit
import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacSessionVerifyTests: XCTestCase {
  func testTheFixtureSourceAppliesWritesAndAnnouncesThem() async throws {
    let source = MacSessionsSource.fixture(MacFixtures.listState)
    let changed = expectation(forNotification: MacSessionsSource.fixtureChanged, object: nil)
    try await source.write("w", "s-mac", .pin(true))
    try await source.write("w", "s-review", .archive(true))
    try await source.write("w", "s-tabs", .rename("Tabs, renamed"))
    try await source.write("w", "s-deploy", .delete(["s-deploy"]))
    await fulfillment(of: [changed], timeout: 1)
    let sessions = source.read().catalog.sessions
    XCTAssertEqual(sessions.first { $0.id == "s-mac" }?.pinned, true)
    XCTAssertEqual(sessions.first { $0.id == "s-review" }?.archived, true)
    XCTAssertEqual(sessions.first { $0.id == "s-tabs" }?.title, "Tabs, renamed")
    XCTAssertNil(sessions.first { $0.id == "s-deploy" })
    XCTAssertTrue(source.changes.contains(MacSessionsSource.fixtureChanged))
  }

  func testTheMenuRouteParses() {
    XCTAssertEqual(MacVerifyRoute(URL(string: "lodymacverify://act/menu?seq=3&title=Pin")!), .act(3, .menu("Pin")))
    XCTAssertNil(MacVerifyRoute(URL(string: "lodymacverify://act/menu?seq=3")!))
  }

  func testTheMenuActionRunsAMenuBarItemThroughTheWindowsResponders() throws {
    let menu = NSMenu()
    let session = NSMenu(title: "Session")
    let pin = MacSessionAction.pin.menuItem("Pin", action: #selector(MacWorkspaceController.performSessionAction(_:)))
    session.addItem(pin)
    let item = NSMenuItem(title: "Session", action: nil, keyEquivalent: "")
    item.submenu = session
    menu.addItem(item)
    var writes: [String] = []
    let source = MacSessionsSource(changes: [], read: { MacFixtures.listState }, write: { _, id, _ in writes.append(id) }, selectWorkspace: { _ in })
    let controller = MainWindowController(environment: MacEnvironment(
      sessions: source, pane: { MacSessionSummaryController(sessionId: $0, sessions: source) }, newSession: { MacPlaceholderController(text: "") },
      requiresAccount: false
    ), sessionId: "s-review")
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    XCTAssertNil(MacVerifyActions.perform(.menu("Pin"), in: window, menu: menu))
    XCTAssertNotNil(MacVerifyActions.perform(.menu("Nope"), in: window, menu: menu))
    let deadline = Date().addingTimeInterval(2)
    while writes.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(writes, ["s-review"])
  }
}
