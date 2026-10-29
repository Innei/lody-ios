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
    init(_ id: String?) { sessionId = id }
    func setStreaming(_ on: Bool) { streaming = on }
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
