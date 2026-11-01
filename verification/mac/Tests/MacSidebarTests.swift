import AppKit
import XCTest
import LodyCore
import LodyData
@testable import LodyMacApp

@MainActor
final class MacNewChatFlowTests: XCTestCase {
  private func host() -> (MacWorkspaceController, NSWindow) {
    let workspace = MacWorkspaceController(environment: MacFixtures.environment)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = workspace
    window.layoutIfNeeded()
    return (workspace, window)
  }

  func testRepeatingNewChatKeepsTheDraftEditorAndText() throws {
    let (workspace, window) = host()
    defer { window.close() }
    workspace.open(nil)
    let original = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    original.string = "Keep my unsent draft"
    original.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: original))
    workspace.open(nil)
    let returned = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    XCTAssertTrue(original === returned, "New Chat resumes the same draft rather than constructing a replacement")
    XCTAssertEqual(returned.string, "Keep my unsent draft")
  }

  func testConversationDetourKeepsTheDraftsProjectAndText() throws {
    let (workspace, window) = host()
    defer { window.close() }
    workspace.open(nil)
    let original = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    original.string = "Keep the lody-ios context"
    original.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: original))
    workspace.open("s-landing")
    workspace.open(nil)
    let returned = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    XCTAssertEqual(returned.string, "Keep the lody-ios context")
    let project = try XCTUnwrap(window.contentView?.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "composer-project" })
    XCTAssertEqual(project.titleOfSelectedItem, "lody-ios")
  }

  func testFreshDraftInheritsTheCurrentSessionsProject() throws {
    let (workspace, window) = host()
    defer { window.close() }
    workspace.open("s-landing")
    workspace.open(nil)
    let project = try XCTUnwrap(window.contentView?.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "composer-project" })
    XCTAssertEqual(project.titleOfSelectedItem, "lody-web")
  }

  func testAnExplicitEmptyDraftConfigurationSurvivesAConversationDetour() throws {
    for id in ["composer-machine", "composer-mode"] {
      let (workspace, window) = host()
      defer { window.close() }
      workspace.open(nil)
      let draft = try XCTUnwrap(workspace.splitViewItems[1].viewController.children.compactMap { $0 as? MacNewSessionController }.first)
      let composer = try XCTUnwrap(draft.children.compactMap { $0 as? MacComposerController }.first)
      let deadline = Date().addingTimeInterval(2)
      while composer.model.form.current.loading, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
      let popup = try XCTUnwrap(composer.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == id })
      popup.selectItem(at: popup.numberOfItems - 1)
      if let action = popup.action { NSApp.sendAction(action, to: popup.target, from: popup) }
      let choice = composer.model.choice
      let machine = composer.model.form.current.machineId
      XCTAssertTrue(composer.model.text.isEmpty)
      workspace.open("s-landing")
      workspace.open(nil)
      XCTAssertEqual(composer.model.form.current.projectId, "p-ios", "explicit configuration is a retained draft even without text")
      XCTAssertEqual(composer.model.form.current.machineId, machine)
      XCTAssertEqual(composer.model.choice, choice)
    }
  }

  func testWorkspaceChangeDiscardsThePreviousPrivateDraft() throws {
    var state = MacFixtures.listState
    let changed = Notification.Name("mac-new-chat-workspace-changed")
    let source = MacSessionsSource(changes: [changed], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    var environment = MacFixtures.environment
    environment.sessions = source
    environment.newSession = { MacNewSessionController(source: source, service: MacComposerFixture.service) }
    let workspace = MacWorkspaceController(environment: environment)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = workspace
    defer { window.close() }
    workspace.open(nil)
    let input = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    input.string = "Private draft in the first workspace"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    state.workspaceId = "w-other"
    NotificationCenter.default.post(name: changed, object: nil)
    let current = try XCTUnwrap(window.contentView?.descendants(MacComposerTextView.self).first)
    XCTAssertEqual(current.string, "", "changing workspace must not expose a retained draft from the old scope")
  }

  func testRemovingTheDraftsProjectDuringADetourBlocksSendWithoutLosingText() throws {
    var state = MacFixtures.listState
    let changed = Notification.Name("mac-new-chat-project-removed")
    let source = MacSessionsSource(changes: [changed], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    var sent = 0
    let service = MacComposerService(options: { workspace, id in
      var options = try await MacComposerFixture.service.options(workspace, id)
      if let project = state.catalog.projects.first(where: { $0.id == id }) {
        options.project = CreateProject(id: project.id, machineId: project.machineId, name: project.name, rootPath: project.rootPath)
      }
      return options
    }, create: { _, _ in sent += 1 })
    var environment = MacFixtures.environment
    environment.sessions = source
    var retained: MacNewSessionController?
    environment.newSession = { let next = MacNewSessionController(source: source, service: service); retained = next; return next }
    let workspace = MacWorkspaceController(environment: environment)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = workspace
    defer { window.close() }
    workspace.open(nil)
    let composer = try XCTUnwrap(retained?.children.compactMap { $0 as? MacComposerController }.first)
    let deadline = Date().addingTimeInterval(2)
    while composer.model.form.current.loading, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    let input = try XCTUnwrap(composer.view.descendants(MacComposerTextView.self).first)
    input.string = "Keep this draft in lody-ios"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    XCTAssertTrue(composer.model.canSend)
    workspace.open("s-landing")
    state.catalog.projects.removeAll { $0.id == "p-ios" }
    NotificationCenter.default.post(name: changed, object: nil)
    workspace.open(nil)
    XCTAssertEqual(input.string, "Keep this draft in lody-ios")
    XCTAssertFalse(composer.model.canSend, "cached creation options cannot authorize a removed project")
    let project = try XCTUnwrap(composer.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "composer-project" })
    XCTAssertTrue(project.titleOfSelectedItem?.contains("lody-ios") == true, "the unavailable original context remains visible")
    input.onSubmit?()
    XCTAssertEqual(sent, 0)
    retained?.selectProject("p-web")
    let resumed = Date().addingTimeInterval(2)
    while composer.model.form.current.loading, Date() < resumed { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    XCTAssertTrue(composer.model.canSend, "an explicit valid project restores sending")
  }
}

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
final class MacPaletteModelTests: XCTestCase {
  func testRemovingTheComputerFilterRestoresTheDisplayedAllComputersScope() throws {
    var state = MacFixtures.listState
    let controller = MacPaletteController(state: state, mode: .projects)
    let filter = try XCTUnwrap(controller.view.descendants(NSPopUpButton.self).first)
    filter.selectItem(withTitle: "Mac mini")
    if let action = filter.action { NSApp.sendAction(action, to: filter.target, from: filter) }
    state.catalog.machineIds.removeAll { $0 == "m-mini" }
    controller.update(state)
    XCTAssertEqual(filter.titleOfSelectedItem, "All computers")
    let table = try XCTUnwrap(controller.view.descendants(NSTableView.self).first)
    XCTAssertEqual(table.numberOfRows, MacPaletteModel(state: state, mode: .projects).items(query: "").count + 1,
                   "the visible scope and actual result filter must agree")
  }

  func testActionsNeverSubstituteAnotherResultAfterTheOriginalDisappears() throws {
    for mode: MacPaletteModel.Mode in [.search, .projects] {
      var state = MacFixtures.listState
      let controller = MacPaletteController(state: state, mode: mode)
      let field = try XCTUnwrap(controller.view.descendants(NSSearchField.self).first)
      field.stringValue = mode == .search ? "Review" : "lody-ios"
      field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
      let menu = try XCTUnwrap(controller.actionsMenu())
      var picked: [MacPaletteModel.Destination] = []
      controller.onPick = { picked.append($0) }
      if mode == .search { state.catalog.sessions.removeAll { $0.id == "s-review" } }
      else { state.catalog.projects.removeAll { $0.id == "p-ios" } }
      field.stringValue = ""
      controller.update(state)
      menu.performActionForItem(at: 0)
      XCTAssertTrue(picked.isEmpty, "an old menu cannot execute the new first result")
    }
  }

  func testChatSearchMatchesBranchesAndExcludesArchivedAndChildSessions() {
    var state = MacFixtures.listState
    state.catalog.sessions.append(SessionItem(id: "child", title: "mac-client child", projectId: "p-ios", parentSessionId: "s-mac"))
    let model = MacPaletteModel(state: state, mode: .search)
    XCTAssertEqual(model.items(query: "  MAC-CLIENT  ", scope: .chats).map(\.id), ["chat:s-mac"])
    XCTAssertTrue(model.items(query: "Archived", scope: .chats).isEmpty)
    XCTAssertTrue(model.items(query: "child", scope: .chats).isEmpty)
  }

  func testProjectScopeDoesNotMixChatsIntoMatchingProjectNames() {
    let model = MacPaletteModel(state: MacFixtures.listState, mode: .search)
    XCTAssertEqual(model.items(query: "lody-ios", scope: .projects).map(\.destination), [.project("p-ios")])
    XCTAssertEqual(Set(model.items(query: "lody-ios", scope: .chats).map(\.id)), ["chat:s-mac", "chat:s-review", "chat:s-tabs"])
  }

  func testProjectComputerFilterUsesCatalogOwnershipAndPreservesProjectFreeChat() {
    let model = MacPaletteModel(state: MacFixtures.listState, mode: .projects)
    XCTAssertEqual(model.items(query: "", machineId: "m-mini").map(\.destination), [.project("p-web")])
    XCTAssertTrue(model.items(query: "").contains { $0.destination == .project(nil) })
    XCTAssertTrue(model.items(query: "no such repository").isEmpty)
  }
}

@MainActor
final class MacSidebarChromeTests: XCTestCase {
  func testThePaletteHeaderClearButtonRestoresResultsAndKeepsSearchOpen() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    let before = sidebar.visibleIds
    sidebar.focusSearch()
    let panel = try XCTUnwrap(window.childWindows?.first { $0.identifier?.rawValue == "command-palette" })
    defer { panel.close() }
    let field = try XCTUnwrap(panel.contentView?.descendants(NSSearchField.self).first)
    field.stringValue = "no matching task"
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    let table = try XCTUnwrap(panel.contentView?.descendants(NSTableView.self).first)
    XCTAssertEqual(table.numberOfRows, 0)
    let clear = try XCTUnwrap(panel.contentView?.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "palette-search-clear" })
    XCTAssertFalse(clear.isHidden)
    clear.performClick(nil)
    XCTAssertEqual(field.stringValue, "")
    XCTAssertGreaterThan(table.numberOfRows, 0)
    XCTAssertTrue(clear.isHidden)
    XCTAssertTrue(window.childWindows?.contains(panel) == true)
    XCTAssertEqual(sidebar.visibleIds, before)
  }

  func testAClosedPaletteCannotApplyALateSelection() {
    let parent = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    defer { parent.close() }
    var picked: [MacPaletteModel.Destination] = []
    let palette = MacPaletteWindowController(source: .fixture(MacFixtures.listState), mode: .search, parent: parent) { picked.append($0) }
    palette.present()
    palette.dismiss()
    palette.content.onPick?(.chat("s-mac"))
    XCTAssertTrue(picked.isEmpty, "a queued selection from a dismissed or invalidated palette must not navigate in a new context")
  }

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

  func testSearchOpensATransientPaletteWithoutFilteringTheSidebar() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    let before = sidebar.visibleIds
    sidebar.focusSearch()
    let panel = try XCTUnwrap(window.childWindows?.first { $0.identifier?.rawValue == "command-palette" })
    defer { panel.close() }
    let field = try XCTUnwrap(panel.contentView?.descendants(NSSearchField.self).first)
    field.stringValue = "Landing"
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    XCTAssertEqual(sidebar.visibleIds, before, "typing in search never filters the underlying navigation tree")
    let table = try XCTUnwrap(panel.contentView?.descendants(NSTableView.self).first)
    XCTAssertEqual(table.numberOfRows, 2, "one group header and the matching conversation")
  }

  func testDismissingSearchLeavesTheCurrentSidebarSelectionIntact() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    sidebar.select(sessionId: "s-review")
    let before = sidebar.outlineView.selectedRow
    sidebar.focusSearch()
    let panel = try XCTUnwrap(window.childWindows?.first { $0.identifier?.rawValue == "command-palette" })
    let close = try XCTUnwrap(panel.contentView?.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "palette-close" })
    close.performClick(nil)
    XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    XCTAssertEqual(sidebar.outlineView.selectedRow, before)
    XCTAssertEqual(sidebar.visibleIds.count, 6)
  }

  func testMachineExpansionKeepsItsHeaderActionsLabeledCorrectly() throws {
    let (sidebar, window) = host()
    defer { window.close() }
    let outline = sidebar.outlineView
    let machine = try XCTUnwrap((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarViewController.Node }.first { $0.kind == .machine })
    outline.collapseItem(machine)
    _ = outline.view(atColumn: 0, row: outline.row(forItem: machine), makeIfNecessary: true)
    outline.expandItem(machine)
    let manage = try XCTUnwrap(sidebar.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "sidebar-manage-projects" })
    XCTAssertEqual(manage.accessibilityLabel(), String(localized: "mac.sidebar.manageProjects", bundle: .lodyMac))
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

  func testCollapsingAndExpandingSidebarPreservesTheWindowFrame() async throws {
    try await checkSidebarWindowFrame(sessionId: "s-mac")
  }

  func testNewDraftSidebarAnimationAlsoPreservesTheWindowFrame() async throws {
    try await checkSidebarWindowFrame(sessionId: nil)
  }

  private func checkSidebarWindowFrame(sessionId: String?) async throws {
    let controller = MainWindowController(environment: MacFixtures.environment, sessionId: sessionId)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    let workspace = try XCTUnwrap(controller.workspace)
    let side = try XCTUnwrap(workspace.splitViewItems.first)
    for width: CGFloat in [760, 1100, 1800] {
      window.setContentSize(NSSize(width: width, height: 720))
      window.layoutIfNeeded()
      let before = window.frame
      XCTAssertEqual(before.width, width, accuracy: 1, "the reading column must not limit resizing the window")
      let resizing = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
        MainActor.assumeIsolated {
          XCTAssertEqual(window.frame.width, before.width, accuracy: 1, "window width stays fixed throughout the animation")
          XCTAssertEqual(window.frame.height, before.height, accuracy: 1, "window height stays fixed throughout the animation")
        }
      }
      defer { NotificationCenter.default.removeObserver(resizing) }
      for collapsed in [true, false] {
        await withCheckedContinuation { continuation in
          NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            side.animator().isCollapsed = collapsed
          }, completionHandler: { continuation.resume() })
        }
        window.layoutIfNeeded()
        XCTAssertEqual(window.frame.width, before.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, before.height, accuracy: 1)
        XCTAssertEqual(window.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(side.isCollapsed, collapsed)
      }
    }
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
  func testTopCommandsUseTheSameRailTypographyAndRowRhythmAsSessions() throws {
    let controller = MainWindowController(environment: MacFixtures.environment, sessionId: "s-mac")
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.layoutIfNeeded()
    let sidebar = try XCTUnwrap(controller.workspace?.sidebar)
    let outline = sidebar.outlineView
    let row = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarViewController.Node)?.id == "s-tabs" })
    let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
    cell.layoutSubtreeIfNeeded()
    let title = try XCTUnwrap(cell.textField)
    let root = try XCTUnwrap(window.contentView)
    let new = try XCTUnwrap(root.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "sidebar-new-session" })
    let newTitle = try XCTUnwrap(new.descendants(NSTextField.self).first)
    let searchRow = try XCTUnwrap(root.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "sidebar-search" })
    let search = try XCTUnwrap(searchRow.descendants(NSTextField.self).first)
    let expectedHeight = outline.rect(ofRow: row).height
    XCTAssertEqual(new.convert(new.bounds, to: root).minX, cell.convert(cell.bounds, to: root).minX, accuracy: 0.5)
    XCTAssertEqual(search.convert(search.bounds, to: root).minX, title.convert(title.bounds, to: root).minX, accuracy: 0.5)
    XCTAssertEqual(search.frame.height, title.frame.height, accuracy: 0.5, "native text fields share an intrinsic height and baseline")
    XCTAssertEqual(newTitle.convert(newTitle.bounds, to: root).minX, title.convert(title.bounds, to: root).minX, accuracy: 0.5)
    XCTAssertEqual(newTitle.firstBaselineOffsetFromTop, title.firstBaselineOffsetFromTop, accuracy: 0.5)
    XCTAssertEqual(search.firstBaselineOffsetFromTop, title.firstBaselineOffsetFromTop, accuracy: 0.5)
    let referenceFont = try XCTUnwrap(title.font)
    for candidate in [newTitle.font, search.font] {
      let font = try XCTUnwrap(candidate)
      XCTAssertEqual(font.pointSize, referenceFont.pointSize)
      XCTAssertEqual(NSFontManager.shared.weight(of: font), NSFontManager.shared.weight(of: referenceFont))
    }
    XCTAssertEqual(search.textColor, title.textColor)
    XCTAssertEqual(newTitle.textColor, title.textColor)
    XCTAssertEqual(new.frame.height, expectedHeight, accuracy: 0.5)
    XCTAssertEqual(searchRow.frame.height, expectedHeight, accuracy: 0.5)
    XCTAssertEqual(abs(new.convert(new.bounds, to: root).midY - searchRow.convert(searchRow.bounds, to: root).midY), expectedHeight, accuracy: 0.5)
  }

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
    let state = MacFixtures.listState
    let changed = Notification.Name("mac-sidebar-expansion-catalog")
    let source = MacSessionsSource(changes: [changed], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let sidebar = SidebarViewController(source: source)
    _ = sidebar.view
    let outline = sidebar.outlineView
    func project() throws -> SidebarViewController.Node {
      try XCTUnwrap((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarViewController.Node }.first { $0.title == "lody-ios" })
    }
    outline.collapseItem(try project())
    NotificationCenter.default.post(name: changed, object: nil)
    XCTAssertFalse(outline.isItemExpanded(try project()))
    XCTAssertFalse(sidebar.visibleIds.contains("s-mac"))
    outline.expandItem(try project())
    XCTAssertTrue(sidebar.visibleIds.contains("s-mac"))
  }

  func testTrailingProjectButtonExpandsAndCollapsesItsSessions() throws {
    let sidebar = SidebarViewController(source: .fixture(MacFixtures.listState))
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentViewController = sidebar
    window.layoutIfNeeded()
    let toggle = try XCTUnwrap(sidebar.view.descendants(NSButton.self).first { $0.accessibilityLabel() == "Collapse lody-ios" })
    let header = try XCTUnwrap(toggle.superview)
    let title = try XCTUnwrap(header.descendants(NSTextField.self).first { $0.stringValue == "lody-ios" })
    XCTAssertGreaterThan(toggle.frame.minX, title.frame.maxX, "the disclosure control follows the project title")
    toggle.performClick(nil)
    XCTAssertFalse(sidebar.visibleIds.contains("s-mac"))
    XCTAssertEqual(toggle.accessibilityLabel(), "Expand lody-ios")
    toggle.performClick(nil)
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
