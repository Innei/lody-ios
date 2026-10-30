import AppKit
import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacSessionMenuTests: XCTestCase {
  private var writes: [String] = []

  private func sessions() -> MacSessionsSource {
    MacSessionsSource(changes: [], read: { MacFixtures.listState }, write: { _, id, write in
      if case .pin(let on) = write { self.writes.append("\(id)/pin:\(on)") }
    }, selectWorkspace: { _ in })
  }

  private func wait(_ done: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
  }

  func testTheMenuBarCarriesSessionAndTabShortcuts() throws {
    let groups = MacShortcutList.groups(from: MacMainMenu.make(target: LodyMacAppDelegate()), appName: "Lody")
    let session = try XCTUnwrap(groups.first { $0.title == String(localized: "mac.menu.session", bundle: .lodyMac) })
    XCTAssertEqual(session.rows.map(\.keys), ["F2", "⌥⌘A", "⌥⌘P", "⇧⌘U", "⌥⌘↑", "⌥⌘↓", "⌘⌫"])
    let window = try XCTUnwrap(groups.first { $0.title == String(localized: "mac.menu.window", bundle: .lodyMac) })
    XCTAssertEqual(window.rows.filter { $0.keys.count == 2 && $0.keys.hasPrefix("⌘") && $0.keys.last!.isNumber }.map(\.keys),
                   (1...9).map { "⌘\($0)" })
  }

  func testMenuActionsActOnTheCurrentTabsSession() async throws {
    let source = sessions()
    let workspace = MacWorkspaceController(environment: MacEnvironment(
      sessions: source, pane: { MacSessionSummaryController(sessionId: $0, sessions: source) }, newSession: { MacPlaceholderController(text: "") }
    ))
    _ = workspace.view
    let item = NSMenuItem(title: "", action: #selector(MacWorkspaceController.performSessionAction(_:)), keyEquivalent: "")
    item.representedObject = MacSessionAction.pin.rawValue
    workspace.open(nil)
    XCTAssertFalse(workspace.validateMenuItem(item))
    workspace.open("s-plan")
    XCTAssertTrue(workspace.validateMenuItem(item))
    XCTAssertEqual(item.title, String(localized: "mac.session.unpin", bundle: .lodyMac))
    workspace.performSessionAction(item)
    try await wait { !writes.isEmpty }
    XCTAssertEqual(writes, ["s-plan/pin:false"])
  }

  func testTheContextMenuActsOnTheClickedRow() throws {
    let sidebar = SidebarViewController(source: sessions())
    _ = sidebar.view
    var acted: [String] = []
    sidebar.onAction = { action, id in acted.append("\(action.rawValue):\(id)") }
    let menu = sidebar.contextMenu(for: "s-review")
    let pin = try XCTUnwrap(menu.items.first { $0.representedObject as? String == MacSessionAction.pin.rawValue })
    XCTAssertEqual(pin.title, String(localized: "mac.session.pin", bundle: .lodyMac))
    XCTAssertEqual(pin.keyEquivalent, "p")
    let read = try XCTUnwrap(menu.items.first { $0.representedObject as? String == MacSessionAction.read.rawValue })
    XCTAssertTrue(read.isEnabled)
    _ = (pin.target as? NSObject)?.perform(pin.action, with: pin)
    XCTAssertEqual(acted, ["pin:s-review"])
  }

  func testReturnOnASelectedRowStartsARename() throws {
    let sidebar = SidebarViewController(source: sessions())
    _ = sidebar.view
    var acted: [String] = []
    sidebar.onAction = { action, id in acted.append("\(action.rawValue):\(id)") }
    sidebar.select(sessionId: "s-tabs")
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                               characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    sidebar.outlineView.keyDown(with: event)
    XCTAssertEqual(acted, ["rename:s-tabs"])
  }

  func testPreviousAndNextFollowTheSidebarOrder() {
    let sidebar = SidebarViewController(source: sessions())
    _ = sidebar.view
    XCTAssertEqual(sidebar.neighbor(of: "s-plan", step: 1), "s-mac")
    XCTAssertEqual(sidebar.neighbor(of: "s-landing", step: -1), "s-tabs")
    XCTAssertNil(sidebar.neighbor(of: "s-deploy", step: 1))
    XCTAssertEqual(sidebar.neighbor(of: nil, step: 1), "s-plan")
  }

  func testTabShortcutsPickByPositionAndNineIsLast() {
    XCTAssertEqual(MainWindowController.tabIndex(tag: 1, count: 3), 0)
    XCTAssertEqual(MainWindowController.tabIndex(tag: 3, count: 3), 2)
    XCTAssertNil(MainWindowController.tabIndex(tag: 4, count: 3))
    XCTAssertEqual(MainWindowController.tabIndex(tag: 9, count: 3), 2)
    XCTAssertNil(MainWindowController.tabIndex(tag: 9, count: 0))
  }
}

@MainActor
final class MacSessionMenuRoutingTests: XCTestCase {
  func testSessionMenuItemsReachTheWorkspaceWhenNothingHasFocus() throws {
    let sessions = MacSessionsSource.fixture(MacFixtures.listState)
    let controller = MainWindowController(environment: MacEnvironment(
      sessions: sessions, pane: { MacSessionSummaryController(sessionId: $0, sessions: sessions) }, newSession: { MacPlaceholderController(text: "") },
      requiresAccount: false
    ), sessionId: "s-plan")
    let window = try XCTUnwrap(controller.window)
    window.makeFirstResponder(nil)
    XCTAssertTrue(controller.supplementalTarget(forAction: #selector(MacWorkspaceController.performSessionAction(_:)), sender: nil) as AnyObject === controller.workspace)
    window.close()
  }
}
