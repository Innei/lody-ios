import AppKit
import XCTest
import LodyCore
import LodyData
@testable import LodyMacKit

@MainActor
final class MacNotificationBaselineTests: XCTestCase {
  private func state(_ workspace: String, loading: Bool, _ sessions: [SessionItem]) -> SessionListState {
    SessionListState(userId: "u", workspaceId: workspace, loading: loading, catalog: SessionCatalog(sessions: sessions))
  }

  func testRestoredCatalogsAndWorkspaceSwitchesNeverNotify() {
    var baseline = MacNotificationBaseline()
    XCTAssertEqual(baseline.next(state("w1", loading: true, [SessionItem(id: "a", title: "A", status: "running")]), onScreen: nil), [])
    XCTAssertEqual(baseline.next(state("w1", loading: false, [SessionItem(id: "a", title: "A", status: "idle")]), onScreen: nil), [])
    XCTAssertEqual(baseline.next(state("w1", loading: false, [SessionItem(id: "a", title: "A", status: "running")]), onScreen: nil), [])
    XCTAssertEqual(
      baseline.next(state("w1", loading: false, [SessionItem(id: "a", title: "A", status: "idle")]), onScreen: nil),
      [.finished(sessionId: "a", title: "A")]
    )
    XCTAssertEqual(baseline.next(state("w2", loading: false, [SessionItem(id: "a", title: "A", status: "running")]), onScreen: nil), [])
    XCTAssertEqual(baseline.next(state("w2", loading: false, [SessionItem(id: "a", title: "A", status: "idle")]), onScreen: nil), [.finished(sessionId: "a", title: "A")])
  }
}

@MainActor
final class MacPermissionFlowTests: XCTestCase {
  private func permission(options: String?, kind: String = "edit", request: String = "r1") throws -> SessionPermission {
    let optionsJSON = options.map { ",\"options\":\($0)" } ?? ""
    let json = """
    [{"id":"a1","role":"assistant","items":[{"itemId":"edit","type":"tool_call","kind":"\(kind)","title":"Edit file","permission":{"pending":true,"requestId":"\(request)"\(optionsJSON)}}]}]
    """
    let entries = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    return try XCTUnwrap(try SessionPermission.first(in: entries))
  }

  func testMissingOptionsLoadFromDetail() async throws {
    let flow = MacPermissionFlow(
      detail: { _ in [.init(optionId: "allow", name: "Allow", kind: "allow_once")] },
      respond: { _, _ in .accepted }
    )
    flow.show(try permission(options: nil))
    XCTAssertEqual(flow.card?.options, [])
    await flow.settled()
    XCTAssertEqual(flow.card?.options.map(\.name), ["Allow"])
  }

  func testAnswersRunOnceAndStaleResultsStayAnswerable() async throws {
    var calls = 0
    var results: [RuntimeContract.RespondPermissionResultState] = [.stale, .accepted]
    let flow = MacPermissionFlow(detail: { _ in nil }, respond: { _, _ in
      calls += 1
      return results.removeFirst()
    })
    let target = try permission(options: #"[{"optionId":"allow","name":"Allow","kind":"allow_once"}]"#)
    flow.show(target)
    flow.answer("allow")
    flow.answer("allow")
    XCTAssertEqual(flow.card?.busy, true)
    await flow.settled()
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(flow.card?.busy, false)
    XCTAssertFalse(flow.card?.error.isEmpty ?? true)
    flow.answer("allow")
    await flow.settled()
    XCTAssertNil(flow.card)
    flow.show(target)
    XCTAssertNil(flow.card, "an accepted request stays hidden until the feed drops it")
  }

  func testTheCardNeverClaimsReturn() throws {
    let target = try permission(options: #"[{"optionId":"allow","name":"Allow","kind":"allow_once"}]"#)
    let card = MacPermissionCard(card: .init(permission: target, options: target.options ?? [], busy: false, error: ""))
    let buttons = card.descendants(NSButton.self)
    XCTAssertFalse(buttons.isEmpty)
    XCTAssertTrue(buttons.allSatisfy { $0.keyEquivalent.isEmpty })
  }
}

@MainActor
final class MacReplyDraftTests: XCTestCase {
  func testRejectedSendsRestoreTheTextAndAcceptedSendsDropIt() {
    var draft = MacDraftHandoff()
    draft.sent("Ship it")
    XCTAssertEqual(draft.restore(current: ""), "Ship it")
    XCTAssertNil(draft.restore(current: ""))
    draft.sent("Again")
    draft.clear()
    XCTAssertNil(draft.restore(current: ""))
    draft.sent("Third")
    XCTAssertNil(draft.restore(current: "typed meanwhile"))
  }

  func testPendingAndFailedSendsRenderInTheTranscript() {
    let pending = #"{"id":"p1","text":"Ship it","attachments":[],"status":"Sending…","failed":false}"#
    let sending = MacTranscriptModel(entriesJSON: "[]", pendingJSON: pending)
    XCTAssertTrue(sending.items.contains { if case .user(_, "Ship it") = $0 { true } else { false } }, "\(sending.items)")
    let failed = MacTranscriptModel(entriesJSON: "[]", pendingJSON: #"{"id":"p1","text":"Ship it","attachments":[],"status":"Couldn't send","failed":true}"#)
    XCTAssertTrue(failed.items.contains { if case .failedSend = $0 { true } else { false } }, "\(failed.items)")
  }
}

@MainActor
final class MacCreateFailureTests: XCTestCase {
  func testAFailedOutboxWriteRecordsAFailedDraftAndToasts() async throws {
    let project = CreateProject(id: "p1", machineId: "m1", name: "lody-ios")
    let agent = CreationAgent(id: "claude", name: "Claude", machineId: "m1", machineName: "Mac Studio", cliType: "builtin", agentType: "claude")
    var form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [project])
    form.open(projectId: "p1", context: nil)
    form.applyOptions(CreationOptions(sessionId: "new-1", project: project, agents: [agent], capabilities: []), chat: false)
    form.selectMachine("m1")
    let draft = try XCTUnwrap(form.draft(sessionId: "new-1"))
    var writes: [String] = []
    var opened: [String] = []
    var toasts: [String] = []
    await MacComposerService.create(
      draft, ["id": "t1", "text": "Hello", "startedAt": 1],
      put: { json in
        writes.append(json)
        return Task { throw OutboxError.scopeExpired }
      },
      opened: { opened.append($0) },
      toast: { toasts.append($0) }
    )
    XCTAssertEqual(writes.count, 2)
    XCTAssertTrue(writes[1].contains("\"failed\""), writes[1])
    XCTAssertEqual(opened, [])
    XCTAssertEqual(toasts.count, 1)
  }
}

@MainActor
final class MacTranscriptReuseTests: XCTestCase {
  func testStreamingUpdatesKeepEarlierRowsAndGrowProseInPlace() {
    let view = MacTranscriptView()
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = [.user(id: "u", text: "Hi"), .prose(id: "p", markdown: "Hel")]
    view.render(model)
    let first = view.rowViews
    model.items = [.user(id: "u", text: "Hi"), .prose(id: "p", markdown: "Hello there"), .notice(id: "n", text: "Oops")]
    view.render(model)
    let second = view.rowViews
    XCTAssertEqual(second.count, 3)
    XCTAssertTrue(first[0] === second[0])
    XCTAssertTrue(first[1] === second[1])
  }
}

@MainActor
final class MacToastTests: XCTestCase {
  func testToastsShowAsABannerInTheWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
    MacToast.show("Couldn't save", kind: "error", in: window)
    let banner = window.contentView?.descendants(NSView.self).first { $0.accessibilityIdentifier() == "toast" }
    XCTAssertNotNil(banner)
    XCTAssertTrue(window.contentView?.descendants(NSTextField.self).contains { $0.stringValue == "Couldn't save" } ?? false)
  }
}

extension NSView {
  func descendants<T: NSView>(_ type: T.Type) -> [T] {
    subviews.flatMap { ([$0 as? T].compactMap { $0 }) + $0.descendants(type) }
  }
}

@MainActor
final class MacWorkspaceChromeTests: XCTestCase {
  func testTabTitlesAndBadgesFollowTheCatalog() {
    let name = Notification.Name("MacWorkspaceChromeTests")
    var state = MacFixtures.listState
    let sessions = MacSessionsSource(changes: [name], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let workspace = MacWorkspaceController(environment: MacEnvironment(
      sessions: sessions, pane: { MacSessionSummaryPane(sessionId: $0, sessions: sessions) }, newSession: { MacPlaceholderController(text: "") }
    ))
    var titles: [String] = []
    var badges: [MacTabBadge?] = []
    workspace.onTitle = { title, _ in titles.append(title) }
    workspace.onBadge = { badges.append($0) }
    _ = workspace.view
    workspace.open("s-review")
    XCTAssertEqual(titles.last, "Review transcript projection")
    XCTAssertEqual(badges.last, .some(nil))
    let index = state.catalog.sessions.firstIndex { $0.id == "s-review" }!
    state.catalog.sessions[index].title = "Review the projection"
    state.catalog.sessions[index].awaitingUserSince = 1
    NotificationCenter.default.post(name: name, object: nil)
    XCTAssertEqual(titles.last, "Review the projection")
    XCTAssertEqual(badges.last, .approval)
    state.catalog.sessions[index].awaitingUserSince = nil
    state.catalog.sessions[index].status = "running"
    NotificationCenter.default.post(name: name, object: nil)
    XCTAssertEqual(badges.last, .working)
  }

  func testTheSidebarSwitchesWorkspaces() throws {
    var state = MacFixtures.listState
    state.workspaces.append(AuthWorkspace(id: "w-side", name: "Side Projects", slug: nil, image: nil))
    var selected: [String] = []
    let sidebar = SidebarViewController(source: MacSessionsSource(
      changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { selected.append($0) }
    ))
    _ = sidebar.view
    let picker = try XCTUnwrap(sidebar.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "sidebar-workspace" })
    XCTAssertFalse(picker.isHidden)
    XCTAssertEqual(picker.itemTitles, ["Innei Lab", "Side Projects"])
    picker.selectItem(at: 1)
    _ = picker.sendAction(picker.action, to: picker.target)
    XCTAssertEqual(selected, ["w-side"])
  }
}

@MainActor
final class MacLayoutTests: XCTestCase {
  func testTheTranscriptStaysPinnedToTheBottomAfterRowsSettle() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let transcript = MacTranscriptView(frame: .zero)
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<6).map { .prose(id: "p\($0)", markdown: "Paragraph \($0)\n\n- one\n- two\n- three") }
    let json = """
    [{"id":"a1","role":"assistant","items":[{"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit file","permission":{"pending":true,"requestId":"r1","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"}]}}]}]
    """
    let entries = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
    let permission = try! SessionPermission.first(in: entries)!
    transcript.render(model, card: .init(permission: permission, options: permission.options ?? [], busy: false, error: ""))
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
    window.contentView = container
    container.addSubview(transcript)
    transcript.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
    window.layoutIfNeeded()
    transcript.layoutSubtreeIfNeeded()
    let scroll = transcript.descendants(NSScrollView.self).first!
    XCTAssertGreaterThan(scroll.documentView!.frame.height, scroll.contentView.bounds.height, "the transcript must overflow")
    XCTAssertTrue(transcript.isScrolledToBottom, "\(scroll.contentView.bounds) in \(scroll.documentView!.frame)")
  }
}

@MainActor
final class MacTranscriptPinTests: XCTestCase {
  func testRowsThatGrowAfterRenderKeepTheTranscriptPinned() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
    window.contentView = transcript
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<12).map { .user(id: "u\($0)", text: "Message \($0)") }
    transcript.render(model)
    window.layoutIfNeeded()
    XCTAssertTrue(transcript.isScrolledToBottom)
    transcript.rowViews.last!.heightAnchor.constraint(equalToConstant: 300).isActive = true
    window.layoutIfNeeded()
    transcript.layoutSubtreeIfNeeded()
    XCTAssertTrue(transcript.isScrolledToBottom)
  }

  func testInsetChangesAfterRenderKeepTheTranscriptPinned() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
    window.contentView = transcript
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = (0..<20).map { .user(id: "u\($0)", text: "Message \($0)") }
    transcript.render(model)
    window.layoutIfNeeded()
    let scroll = transcript.descendants(NSScrollView.self).first!
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsets(top: 52, left: 0, bottom: 0, right: 0)
    window.layoutIfNeeded()
    XCTAssertTrue(transcript.isScrolledToBottom, "\(scroll.contentView.bounds) in \(scroll.documentView!.frame)")
  }
}
