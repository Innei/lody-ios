import AppKit
import XCTest
import LodyData
@testable import LodyMacApp

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

  func testProjectsKeepTheirSessionsTogetherAndPinnedFirst() {
    let model = MacSidebarModel(state: state())
    XCTAssertEqual(model.groups.map(\.title), ["lody-ios", "website"])
    XCTAssertEqual(model.groups[0].rows.map(\.id), ["new", "old"])
    XCTAssertEqual(model.groups[1].rows.map(\.id), ["pin", "site"])
    XCTAssertEqual(model.needsApproval, 1)
    XCTAssertFalse(model.groups.flatMap(\.rows).contains { ["child", "gone"].contains($0.id) })
  }

  func testTheSameRepositoryOnTwoMachinesDoesNotMixItsSessions() {
    var current = state()
    current.catalog.sessions[0].machineId = "studio"
    current.catalog.sessions[1].machineId = "mini"
    let model = MacSidebarModel(state: current)
    let projects = model.groups.filter { $0.title == "lody-ios" }
    XCTAssertEqual(projects.count, 2)
    XCTAssertEqual(Set(projects.flatMap(\.rows).map(\.id)), ["new", "old"])
    XCTAssertTrue(projects.allSatisfy { $0.rows.count == 1 })
  }

  func testSearchFindsBranchContextAndExcludesUnrelatedSessions() {
    var current = state()
    current.catalog.sessions[1].branchName = "feature/glass"
    let model = MacSidebarModel(state: current, query: "  feature/glass  ")
    XCTAssertEqual(model.groups.flatMap(\.rows).map(\.id), ["new"])
    XCTAssertTrue(model.pinned.isEmpty)
  }

  func testSearchKeepsMatchingSessionsOnly() {
    let model = MacSidebarModel(state: state(), query: "landing")
    XCTAssertTrue(model.pinned.isEmpty)
    XCTAssertEqual(model.groups.flatMap(\.rows).map(\.id), ["site"])
  }
}

@MainActor
final class MacSidebarChromeTests: XCTestCase {
  private func host() -> (SidebarViewController, NSWindow) {
    let workspace = MacWorkspaceController(environment: MacFixtures.environment)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = workspace
    window.layoutIfNeeded()
    return (workspace.sidebar, window)
  }

  func testNewSessionButtonOpensTheDraftFromTheSidebar() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    var opened = 0
    sidebar.onNewSession = { opened += 1 }
    _ = sidebar.view
    let button = try XCTUnwrap(window.contentView?.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "sidebar-new-session" })
    XCTAssertGreaterThanOrEqual(button.frame.width, 28)
    XCTAssertGreaterThanOrEqual(button.frame.height, 28)
    button.performClick(nil)
    XCTAssertEqual(opened, 1)
  }

  func testFocusingSearchKeepsTheProjectListInPlace() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    let search = try XCTUnwrap(window.contentView?.descendants(NSSearchField.self).first { $0.accessibilityIdentifier() == "sidebar-search" })
    XCTAssertFalse(search.isHidden, "search is directly available without another navigation step")
    let outline = sidebar.outlineView
    let row = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarViewController.Node)?.id == "s-mac" })
    let before = outline.convert(outline.rect(ofRow: row), to: sidebar.view).minY
    sidebar.focusSearch()
    window.layoutIfNeeded()
    let after = outline.convert(outline.rect(ofRow: row), to: sidebar.view).minY
    XCTAssertNotNil(search.currentEditor(), "the Find command focuses the existing native search field")
    XCTAssertEqual(before, after, accuracy: 1, "focusing search must not push the project list down")
    search.stringValue = "Landing"
    sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    XCTAssertEqual(sidebar.visibleIds, ["s-landing"])
  }

  func testChoosingAProjectFiltersTheVisibleSessions() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    let filter = try XCTUnwrap(window.contentView?.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "sidebar-filter" })
    let menu = try XCTUnwrap(filter.menu)
    let project = try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "p-web" })
    menu.performActionForItem(at: project)
    XCTAssertEqual(sidebar.visibleIds, ["s-landing", "s-deploy"])
  }

  func testEmptyProjectResultsKeepTheFilterAvailableToLeaveTheScope() throws {
    var state = MacFixtures.listState
    state.catalog.projects.append(SessionProject(id: "empty", name: "Empty project"))
    let sidebar = SidebarViewController(source: .fixture(state))
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = sidebar
    window.layoutIfNeeded()
    let filter = try XCTUnwrap(sidebar.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "sidebar-filter" })
    let menu = try XCTUnwrap(filter.menu)
    menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "empty" }))
    XCTAssertTrue(sidebar.visibleIds.isEmpty)
    window.layoutIfNeeded()
    XCTAssertNotNil(sidebar.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "sidebar-filter" })
    let all = try XCTUnwrap(filter.menu?.items.firstIndex { ($0.representedObject as? String) == "" })
    filter.menu?.performActionForItem(at: all)
    XCTAssertEqual(sidebar.visibleIds.count, 6)
  }

  func testOpeningAWorkspacePreservesTheInitialWindowSize() throws {
    let controller = MainWindowController(environment: MacFixtures.environment, sessionId: "s-mac")
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.layoutIfNeeded()
    XCTAssertEqual(controller.workspace?.sidebar.view.frame.width ?? 0, 320, accuracy: 1)
    XCTAssertGreaterThanOrEqual(window.frame.width, 1100)
    XCTAssertGreaterThanOrEqual(window.frame.height, 720)
  }

  func testFilteringAndCollapsingRefreshTheToolbarNavigation() throws {
    let controller = MainWindowController(environment: MacFixtures.environment, sessionId: "s-mac")
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.layoutIfNeeded()
    let navigation = try XCTUnwrap(window.toolbar?.items.compactMap { $0.view as? NSSegmentedControl }.first)
    let filter = try XCTUnwrap(window.contentView?.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "sidebar-filter" })
    let menu = try XCTUnwrap(filter.menu)
    let project = try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "p-web" })
    XCTAssertTrue(navigation.isEnabled(forSegment: 1))
    menu.performActionForItem(at: project)
    XCTAssertTrue(navigation.isEnabled(forSegment: 1), "a filtered-out selection can navigate to the first result")
    let all = try XCTUnwrap(filter.menu?.items.firstIndex { ($0.representedObject as? String) == "" })
    filter.menu?.performActionForItem(at: all)
    controller.workspace?.open("s-review")
    XCTAssertTrue(navigation.isEnabled(forSegment: 1))
    let outline = try XCTUnwrap(controller.workspace?.sidebar.outlineView)
    let working = try XCTUnwrap((0..<outline.numberOfRows).map { outline.item(atRow: $0) }.first { ($0 as? SidebarViewController.Node)?.title == "lody-ios" })
    outline.collapseItem(working)
    XCTAssertTrue(navigation.isEnabled(forSegment: 1), "a hidden selection can navigate to another visible project")
  }
}

@MainActor
final class MacSidebarStatusTests: XCTestCase {
  private func cell(_ status: String) throws -> SidebarSessionCell {
    var state = MacFixtures.listState
    state.catalog.sessions = [SessionItem(id: "one", title: "Unread result", status: status, lastMessageAt: 100, lastReadAt: 0)]
    let row = try XCTUnwrap(MacSidebarModel(state: state).groups.flatMap(\.rows).first)
    return SidebarSessionCell(row: row)
  }

  func testUnreadErrorsAndIdleSessionsDoNotClaimCompletion() throws {
    let failed = [try cell("error").accessibilityHelp() ?? ""]
    XCTAssertTrue(failed.contains("Failed"))
    XCTAssertFalse(failed.contains("Done"))
    XCTAssertFalse([try cell("idle").accessibilityHelp() ?? ""].contains("Done"))
    XCTAssertTrue([try cell("completed").accessibilityHelp() ?? ""].contains("Done"))
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
  func testProjectAndSessionTextShareARailWithoutExtraIndentation() throws {
    let sidebar = SidebarViewController(source: .fixture(MacFixtures.listState))
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = sidebar
    window.layoutIfNeeded()
    let outline = sidebar.outlineView
    let projectRow = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarViewController.Node)?.title == "lody-ios" })
    let sessionRow = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarViewController.Node)?.id == "s-mac" })
    func title(_ row: Int, _ text: String) throws -> NSTextField {
      let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true))
      cell.layoutSubtreeIfNeeded()
      return try XCTUnwrap(cell.descendants(NSTextField.self).first { $0.stringValue == text })
    }
    let folder = try title(projectRow, "lody-ios")
    let session = try title(sessionRow, "Build the AppKit sidebar")
    XCTAssertEqual(folder.convert(folder.bounds, to: outline).minX, session.convert(session.bounds, to: outline).minX, accuracy: 1)
    XCTAssertLessThanOrEqual(outline.rect(ofRow: sessionRow).height, 34)
  }
}

@MainActor
final class MacSidebarExpansionTests: XCTestCase {
  func testCollapsedProjectsStayCollapsedAcrossReloads() throws {
    let sidebar = SidebarViewController(source: .fixture(MacFixtures.listState))
    _ = sidebar.view
    let outline = sidebar.outlineView
    func project() throws -> SidebarViewController.Node {
      try XCTUnwrap((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarViewController.Node }.first { $0.title == "lody-ios" })
    }
    outline.collapseItem(try project())
    sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    XCTAssertFalse(outline.isItemExpanded(try project()))
    XCTAssertFalse(sidebar.visibleIds.contains("s-mac"))
    outline.expandItem(try project())
    XCTAssertTrue(sidebar.visibleIds.contains("s-mac"))
  }

  func testArchiveButtonShowsOnlyArchivedSessionsAndCanReturn() throws {
    let workspace = MacWorkspaceController(environment: MacFixtures.environment)
    _ = workspace.view
    let button = try XCTUnwrap(workspace.sidebar.bottomAccessory.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "sidebar-archive" })
    button.performClick(nil)
    XCTAssertEqual(workspace.sidebar.visibleIds, ["s-old"])
    button.performClick(nil)
    XCTAssertFalse(workspace.sidebar.visibleIds.contains("s-old"))
    XCTAssertTrue(workspace.sidebar.visibleIds.contains("s-mac"))
  }
}

@MainActor
final class MacSidebarApprovalTests: XCTestCase {
  private func state() -> SessionListState {
    var catalog = SessionCatalog()
    catalog.sessions = [
      SessionItem(id: "late", title: "Late", awaitingUserSince: 30),
      SessionItem(id: "calm", title: "Calm"),
      SessionItem(id: "early", title: "Early", awaitingUserSince: 10),
      SessionItem(id: "gone", title: "Gone", archived: true, awaitingUserSince: 5),
    ]
    return SessionListState(userId: "u", workspaceId: "w", catalog: catalog)
  }

  func testApprovalsQueueByLongestWait() {
    XCTAssertEqual(MacSidebarModel(state: state()).approvals, ["early", "late"])
  }

  func testAWaitingSessionCanBeOpenedDirectlyFromTheActiveList() throws {
    let current = state()
    let sidebar = SidebarViewController(source: MacSessionsSource(changes: [], read: { current }, write: { _, _, _ in }, selectWorkspace: { _ in }))
    var opened: [String?] = []
    sidebar.onSelect = { opened.append($0) }
    _ = sidebar.view
    let outline = sidebar.outlineView
    let index = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarViewController.Node)?.id == "early" })
    outline.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    XCTAssertEqual(opened, ["early"])
  }
}
