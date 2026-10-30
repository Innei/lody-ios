import XCTest
import LodyData
@testable import LodyMacKit

final class MacSidebarTests: XCTestCase {
  private func state() -> SessionListState {
    var catalog = SessionCatalog()
    catalog.projects = [SessionProject(id: "p1", name: "lody-ios"), SessionProject(id: "p2", name: "website")]
    catalog.sessions = [
      SessionItem(id: "old", title: "Old work", projectId: "p1", lastMessageAt: 10),
      SessionItem(id: "new", title: "New work", status: "running", projectId: "p1", lastMessageAt: 30),
      SessionItem(id: "site", title: "Landing page", projectId: "p2", lastMessageAt: 20, awaitingUserSince: 19),
      SessionItem(id: "pin", title: "Pinned plan", pinned: true, projectId: "p2", lastMessageAt: 5),
      SessionItem(id: "gone", title: "Archived", archived: true, projectId: "p1", lastMessageAt: 40),
      SessionItem(id: "child", title: "Sub agent", projectId: "p1", parentSessionId: "new", lastMessageAt: 50),
    ]
    return SessionListState(userId: "u", workspaceId: "w", catalog: catalog)
  }

  func testGroupsFollowRecencyAndPinnedSessionsSitAbove() {
    let model = MacSidebarModel(state: state())
    XCTAssertEqual(model.pinned.map(\.id), ["pin"])
    XCTAssertEqual(model.groups.map(\.title), ["lody-ios", "website"])
    XCTAssertEqual(model.groups[0].rows.map(\.id), ["new", "old"])
    XCTAssertEqual(model.groups[1].rows.map(\.id), ["site"])
    XCTAssertEqual(model.needsApproval, 1)
    XCTAssertTrue(model.groups[1].rows[0].attention)
    XCTAssertEqual(model.groups[0].rows[0].status, "running")
  }

  func testSearchKeepsMatchingSessionsOnly() {
    let model = MacSidebarModel(state: state(), query: "landing")
    XCTAssertTrue(model.pinned.isEmpty)
    XCTAssertEqual(model.groups.map(\.title), ["website"])
    XCTAssertEqual(model.groups[0].rows.map(\.id), ["site"])
  }
}

@MainActor
final class MacTabCoordinatorTests: XCTestCase {
  private final class Tab: MacStreamingTab {
    var sessionId: String?
    var streaming = false
    var isOnScreen = true
    init(_ id: String?) { sessionId = id }
    func setStreaming(_ on: Bool) { streaming = on }
  }

  func testAMinimizedOrHiddenSelectedTabIsNotOnScreen() {
    let coordinator = MacTabCoordinator()
    let tab = Tab("s1")
    coordinator.add(tab)
    coordinator.select(tab)
    XCTAssertEqual(coordinator.visibleSession, "s1")
    tab.isOnScreen = false
    XCTAssertEqual(coordinator.streamingSession, "s1")
    XCTAssertNil(coordinator.visibleSession)
  }

  func testOnlyTheSelectedTabStreams() {
    let coordinator = MacTabCoordinator()
    let first = Tab("s1"), second = Tab("s2")
    coordinator.add(first)
    coordinator.add(second)
    coordinator.select(first)
    XCTAssertTrue(first.streaming)
    XCTAssertFalse(second.streaming)
    XCTAssertEqual(coordinator.streamingSession, "s1")
    coordinator.select(second)
    XCTAssertFalse(first.streaming)
    XCTAssertTrue(second.streaming)
    XCTAssertEqual(coordinator.streamingSession, "s2")
  }

  func testClosingTheSelectedTabStopsStreamingAndBackgroundTabsReadTheCatalog() {
    let coordinator = MacTabCoordinator()
    let first = Tab("s1"), second = Tab("s2")
    coordinator.add(first)
    coordinator.add(second)
    coordinator.select(second)
    coordinator.remove(second)
    XCTAssertFalse(second.streaming)
    XCTAssertNil(coordinator.streamingSession)
    var catalog = SessionCatalog()
    catalog.sessions = [SessionItem(id: "s1", status: "running")]
    XCTAssertEqual(coordinator.status(of: first, catalog: catalog), "running")
  }
}

@MainActor
final class MacWorkspaceStreamingTests: XCTestCase {
  private final class Pane: NSViewController, MacSessionPane {
    var streaming = false
    override func loadView() { view = NSView() }
    func setStreaming(_ on: Bool) { streaming = on }
  }

  func testASessionOpenedInAnEmptySelectedTabStreams() {
    var panes: [Pane] = []
    let environment = MacEnvironment(
      sessions: .fixture(MacFixtures.listState),
      pane: { _ in
        let pane = Pane()
        panes.append(pane)
        return pane
      },
      newSession: { MacPlaceholderController(text: "") }
    )
    let coordinator = MacTabCoordinator()
    let workspace = MacWorkspaceController(environment: environment)
    _ = workspace.view
    coordinator.add(workspace)
    coordinator.select(workspace)
    workspace.open("s-mac")
    XCTAssertEqual(panes.map(\.streaming), [true])
    XCTAssertEqual(coordinator.streamingSession, "s-mac")
    workspace.open("s-review")
    XCTAssertEqual(panes.map(\.streaming), [false, true])
  }
}

@MainActor
final class MacWindowTabTests: XCTestCase {
  func testNewTabsJoinTheEndOfTheGroup() throws {
    let first = MainWindowController(environment: MacFixtures.environment, sessionId: "s-mac")
    let second = first.addTab(sessionId: "s-landing")
    let third = first.addTab(sessionId: "s-plan")
    defer { [first, second, third].forEach { $0.window?.close() } }
    let titles = try XCTUnwrap(first.window?.tabbedWindows).map(\.title)
    XCTAssertEqual(titles, ["Catalog · Build the AppKit sidebar", "Catalog · Landing page copy", "Catalog · Q4 roadmap"])
  }
}

@MainActor
final class MacSidebarLayoutTests: XCTestCase {
  func testSectionHeadersSitCentredInShorterRows() throws {
    let sidebar = SidebarViewController(source: .fixture(MacFixtures.listState))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 800), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentViewController = sidebar
    window.layoutIfNeeded()
    let outline = try XCTUnwrap(sidebar.view.descendants(NSOutlineView.self).first)
    outline.layoutSubtreeIfNeeded()
    var headers = 0
    for row in 0..<outline.numberOfRows where outline.isExpandable(outline.item(atRow: row)) {
      let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true))
      cell.superview?.layoutSubtreeIfNeeded()
      let label = try XCTUnwrap(([cell] + cell.descendants(NSTextField.self)).compactMap { $0 as? NSTextField }.first { !$0.stringValue.isEmpty })
      let labelMid = label.convert(label.bounds, to: outline).midY
      let rect = outline.rect(ofRow: row)
      XCTAssertEqual(label.frame.height, label.intrinsicContentSize.height, accuracy: 1, "\(label.stringValue) keeps its text height")
      XCTAssertEqual(labelMid, rect.midY, accuracy: 2, "\(label.stringValue) is centred in its row")
      XCTAssertLessThan(rect.height, outline.rect(ofRow: row + 1).height, "\(label.stringValue) row is shorter than a session row")
      headers += 1
    }
    XCTAssertEqual(headers, 3)
  }
}
