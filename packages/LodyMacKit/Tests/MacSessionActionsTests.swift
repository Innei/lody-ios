import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacSessionActionsTests: XCTestCase {
  private var writes: [String] = []
  private var toasts: [String] = []
  private var blocked: [String] = []
  private var confirmations: [Int] = []
  private var renameTo: String? = nil
  private var confirm = true
  private var failing = false

  private let state: SessionListState = {
    var state = SessionListState(userId: "u", workspaceId: "w")
    state.catalog.sessions = [
      SessionItem(id: "s1", title: "Ship it", status: "idle", projectId: "w:p1", lastMessageAt: 10, lastReadAt: 5),
      SessionItem(id: "s1-tab", status: "completed", parentSessionId: "s1"),
      SessionItem(id: "s2", title: "Busy", status: "running", archived: false, pinned: true, projectId: "w:unassigned", lastMessageAt: 10, lastReadAt: 20),
    ]
    return state
  }()

  private func actions() -> MacSessionActions {
    let state = state
    let source = MacSessionsSource(changes: [], read: { state }, write: { workspace, id, write in
      if self.failing { throw CocoaError(.fileWriteUnknown) }
      self.writes.append("\(workspace)/\(id)/\(Self.describe(write))")
    }, selectWorkspace: { _ in })
    return MacSessionActions(source: source, prompts: MacSessionPrompts(
      rename: { _ in self.renameTo },
      confirmDelete: { _, tabs in
        self.confirmations.append(tabs)
        return self.confirm
      },
      blocked: { self.blocked.append($0.id) },
      toast: { message, kind in self.toasts.append("\(kind):\(message)") }
    ), now: { 100 })
  }

  private static func describe(_ write: SessionWrite) -> String {
    switch write {
    case .archive(let on): "archive:\(on)"
    case .pin(let on): "pin:\(on)"
    case .read(let at): "read:\(Int(at))"
    case .rename(let title): "rename:\(title)"
    case .delete(let ids): "delete:\(ids.joined(separator: ","))"
    }
  }

  func testTitlesFollowTheSessionAndReadNeedsUnread() {
    let actions = actions()
    XCTAssertEqual(actions.title(.pin, sessionId: "s1"), String(localized: "mac.session.pin", bundle: .lodyMac))
    XCTAssertEqual(actions.title(.pin, sessionId: "s2"), String(localized: "mac.session.unpin", bundle: .lodyMac))
    XCTAssertEqual(actions.title(.archive, sessionId: "s1"), String(localized: "mac.session.archive", bundle: .lodyMac))
    XCTAssertTrue(actions.isEnabled(.read, sessionId: "s1"))
    XCTAssertFalse(actions.isEnabled(.read, sessionId: "s2"))
    XCTAssertFalse(actions.isEnabled(.pin, sessionId: nil))
  }

  func testPinArchiveAndReadWriteTheirChange() async {
    let actions = actions()
    await actions.perform(.pin, sessionId: "s1")
    await actions.perform(.pin, sessionId: "s2")
    await actions.perform(.archive, sessionId: "s1")
    await actions.perform(.read, sessionId: "s1")
    await actions.perform(.read, sessionId: "s2")
    XCTAssertEqual(writes, ["w/s1/pin:true", "w/s2/pin:false", "w/s1/archive:true", "w/s1/read:100"])
    XCTAssertEqual(toasts, ["info:" + String(localized: "mac.session.archived", bundle: .lodyMac)])
  }

  func testRenameTrimsAndIgnoresEmptyOrUnchangedTitles() async {
    let actions = actions()
    renameTo = "  New name  "
    await actions.perform(.rename, sessionId: "s1")
    renameTo = "   "
    await actions.perform(.rename, sessionId: "s1")
    renameTo = "Ship it"
    await actions.perform(.rename, sessionId: "s1")
    renameTo = nil
    await actions.perform(.rename, sessionId: "s1")
    XCTAssertEqual(writes, ["w/s1/rename:New name"])
  }

  func testDeleteConfirmsAndTakesChildTabs() async {
    let actions = actions()
    confirm = false
    await actions.perform(.delete, sessionId: "s1")
    XCTAssertTrue(writes.isEmpty)
    confirm = true
    await actions.perform(.delete, sessionId: "s1")
    XCTAssertEqual(confirmations, [1, 1])
    XCTAssertEqual(writes, ["w/s1/delete:s1,s1-tab"])
    XCTAssertEqual(toasts.last, "info:" + String(localized: "mac.session.deleted", bundle: .lodyMac))
  }

  func testARunningSessionExplainsInsteadOfDeleting() async {
    let actions = actions()
    await actions.perform(.delete, sessionId: "s2")
    XCTAssertEqual(blocked, ["s2"])
    XCTAssertTrue(confirmations.isEmpty)
    XCTAssertTrue(writes.isEmpty)
  }

  func testAFailedWriteShowsAnError() async {
    let actions = actions()
    failing = true
    await actions.perform(.pin, sessionId: "s1")
    XCTAssertEqual(toasts, ["error:" + String(localized: "mac.session.pinFailed", bundle: .lodyMac)])
  }
}
