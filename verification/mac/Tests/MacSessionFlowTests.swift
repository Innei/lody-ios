import AppKit
import XCTest
import LodyCore
import LodyData
@testable import LodyMacApp

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
  func testAValidAgentQuestionRendersItsChoicesInsteadOfAnOptionsError() throws {
    let target = SessionPermission(
      entryId: "a", itemId: "q", requestId: "request-question", kind: "ask_user_question", title: "Choose a destination", path: nil,
      options: [.init(optionId: "allow", name: "Continue", kind: "allow_once")],
      questionMeta: .init(questions: [
        .init(id: "destination", header: "Destination", question: "Where should this ship?",
              options: [.init(label: "TestFlight", description: "Beta testers", preview: nil)],
              multiSelect: false, allowCustomAnswer: true, isSecret: false),
      ], allowCustomAnswer: true)
    )
    let flow = MacPermissionFlow(detail: { _ in nil }, respond: { _, _ in .accepted })
    flow.show(target)
    let card = try XCTUnwrap(flow.card)
    XCTAssertTrue(card.error.isEmpty, "valid questions must remain answerable: \(card.error)")
    let view = MacPermissionCard(card: card)
    XCTAssertTrue(view.descendants(NSButton.self).contains { $0.accessibilityIdentifier() == "question-option-0" })
  }

  func testQuestionSubmissionKeepsMultiSelectAndCustomAnswersAndRequiresALiveRequest() async throws {
    let target = SessionPermission(
      entryId: "a", itemId: "q", requestId: "r", kind: "ask_user_question", title: "Shipping", path: nil,
      options: [.init(optionId: "allow", name: "Continue", kind: "allow_once")],
      questionMeta: .init(questions: [
        .init(id: "targets", header: "Targets", question: "Where?", options: [
          .init(label: "iOS", description: nil, preview: nil), .init(label: "Mac", description: nil, preview: nil),
        ], multiSelect: true, allowCustomAnswer: false, isSecret: nil),
        .init(id: "notes", header: "Notes", question: "Anything else?", options: [], multiSelect: false, allowCustomAnswer: true, isSecret: nil),
      ], allowCustomAnswer: true)
    )
    var answers: [[String: RuntimeContract.JSONValue]] = []
    let flow = MacPermissionFlow(detail: { _ in nil }, respond: { _, _ in XCTFail("questions need answers"); return .accepted }, respondQuestions: { request, option, value in
      XCTAssertEqual(request.requestId, "r")
      XCTAssertEqual(option, "allow")
      answers.append(value)
      return .accepted
    })
    flow.show(target)
    flow.question(.submit)
    XCTAssertFalse(flow.card?.busy ?? true, "incomplete answers cannot submit")
    flow.question(.select(1))
    flow.question(.select(0))
    flow.question(.page(1))
    flow.question(.text("  Beta first  "))
    flow.show(target, ready: false)
    flow.question(.submit)
    XCTAssertTrue(answers.isEmpty)
    flow.show(target, ready: true)
    flow.question(.submit)
    flow.question(.submit)
    await flow.settled()
    XCTAssertEqual(answers, [["targets": .array([.string("iOS"), .string("Mac")]), "notes": .string("Beta first")]])
    XCTAssertNil(flow.card)
  }

  func testQuestionCardKeepsTheSameTextFieldAcrossEditsAndBusyUpdates() throws {
    let meta = SessionPermission.Questions(questions: [
      .init(id: "q", header: "Answer", question: "What next?", options: [], multiSelect: false, allowCustomAnswer: true, isSecret: false),
    ], allowCustomAnswer: true)
    let target = SessionPermission(entryId: "a", itemId: "q", requestId: "r", kind: "ask_user_question", title: "Answer", path: nil,
                                   options: [.init(optionId: "allow", name: "Continue", kind: "allow_once")], questionMeta: meta)
    var card = MacPermissionFlow.Card(permission: target, options: target.options ?? [], busy: false, error: "", questions: MacQuestionDraft(meta: meta))
    let view = MacPermissionCard(card: card)
    let original = try XCTUnwrap(view.descendants(NSTextField.self).first { $0.accessibilityIdentifier() == "question-custom" })
    card.questions?.setText("Keep typing")
    view.update(card)
    card.busy = true
    view.update(card)
    let current = try XCTUnwrap(view.descendants(NSTextField.self).first { $0.accessibilityIdentifier() == "question-custom" })
    XCTAssertTrue(current === original)
    XCTAssertEqual(current.stringValue, "Keep typing")
    XCTAssertFalse(current.isEnabled)
  }

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
final class MacRunControlTests: XCTestCase {
  func testStopUsesTheOriginalTurnOnceAndWaitsForTheFeedToFinish() async throws {
    var state = MacFixtures.listState
    state.catalog.sessions[0].status = "running"
    let session = state.catalog.sessions[0]
    let sessions = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    var requests: [[String: Any]] = []
    let bridge = MacReplyBridge(sessionId: session.id, sessions: sessions, controlRequest: { payload in
      requests.append(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]))
      return #"{"state":"stopped"}"#
    })
    _ = bridge.composer.view
    var feed = SessionFeedState(status: "live")
    feed.transcript.unfinishedTurnId = "turn-owned"
    bridge.update(feed)
    bridge.composer.onStop?()
    bridge.composer.onStop?()
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?["sessionId"] as? String, session.id)
    XCTAssertEqual(requests.first?["machineId"] as? String, session.machineId)
    XCTAssertEqual(requests.first?["turnId"] as? String, "turn-owned")
    XCTAssertTrue(bridge.composer.model.run.running)
    XCTAssertTrue(bridge.composer.model.run.stopping, "an acknowledgement is not the final feed")
    feed.transcript.unfinishedTurnId = nil
    state.catalog.sessions[0].status = "idle"
    bridge.update(feed)
    XCTAssertFalse(bridge.composer.model.run.running)
  }

  func testAnUnfinishedLiveTurnOffersStopAndAnIdleTurnHidesIt() throws {
    var state = MacFixtures.listState
    state.catalog.sessions[0].status = "running"
    let id = state.catalog.sessions[0].id
    let sessions = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let bridge = MacReplyBridge(sessionId: id, sessions: sessions)
    _ = bridge.composer.view
    var feed = SessionFeedState(status: "live")
    feed.transcript.unfinishedTurnId = "turn-active"
    bridge.update(feed)
    let stop = try XCTUnwrap(bridge.composer.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-stop" })
    XCTAssertFalse(stop.isHidden)
    XCTAssertTrue(stop.isEnabled)
    state.catalog.sessions[0].status = "idle"
    feed.transcript.unfinishedTurnId = nil
    bridge.update(feed)
    XCTAssertTrue(stop.isHidden)
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
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
    window.contentView = view
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
final class MacQueueTests: XCTestCase {
  func testQueueEditsKeepTheirLeaseAndOriginalAttachmentNamesUntilSaved() async throws {
    var item = RuntimeContract.SessionQueueItem(id: "cid-one", revision: "r1", messageId: "turn-one", text: "Before", attachments: ["notes.txt"], editing: false)
    var savedText = ""
    let service = MacQueueService(request: { params in
      switch params {
      case .begin(let request):
        XCTAssertEqual(request.id, "cid-one")
        item.editing = true
        item.editToken = request.editToken
        item.revision = "r2"
      case .save(let request):
        XCTAssertEqual(request.revision, "r2")
        XCTAssertEqual(request.editToken, item.editToken)
        savedText = request.text
        item.text = request.text
        item.editing = false
        item.editToken = nil
      default: break
      }
      return .init(state: .ready, items: [item])
    })
    let model = MacQueueModel(sessionId: "session-one", userId: "u", service: service)
    await model.reload()
    await model.begin(try XCTUnwrap(model.items.first))
    XCTAssertEqual(model.editing?.attachments, ["notes.txt"])
    model.text = "After"
    await model.save()
    XCTAssertEqual(savedText, "After")
    XCTAssertEqual(model.items.first?.text, "After")
    XCTAssertEqual(model.items.first?.attachments, ["notes.txt"])
    XCTAssertNil(model.editing)
  }

  func testAnUnknownQueueWriteBlocksFurtherMutationsUntilAnAuthoritativeReload() async throws {
    let item = RuntimeContract.SessionQueueItem(id: "cid", revision: "r", text: "Keep", attachments: [], editing: false)
    var mutations = 0
    let model = MacQueueModel(sessionId: "s", userId: "u", service: .init(request: { request in
      if case .list = request { return .init(state: .ready, items: [item]) }
      mutations += 1
      return .init(state: .unknown, items: [])
    }))
    await model.reload()
    await model.remove(item)
    await model.remove(item)
    XCTAssertTrue(model.blocked)
    XCTAssertFalse(model.error.isEmpty)
    XCTAssertEqual(mutations, 1)
    await model.reload()
    XCTAssertFalse(model.blocked)
    XCTAssertEqual(model.items.map(\.text), ["Keep"])
  }

  func testQueuePreferenceChangesReachTheActualSendContextWithoutReopeningTheSession() {
    let state = MacFixtures.listState
    let session = state.catalog.sessions[0]
    let sender = SessionSender(sessionId: session.id, store: nil, services: OutboxSession.shared.services, inflight: OutboxInflight())
    var behavior = "guide"
    let source = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let bridge = MacReplyBridge(sessionId: session.id, sessions: source, sender: sender, queuedBehavior: { behavior })
    var feed = SessionFeedState(status: "live")
    feed.transcript.unfinishedTurnId = "active"
    bridge.update(feed)
    XCTAssertEqual(sender.inputs.context.queuedMessageBehavior, "guide")
    behavior = "queue"
    NotificationCenter.default.post(name: .lodyPreferencesDidChange, object: nil)
    XCTAssertEqual(sender.inputs.context.queuedMessageBehavior, "queue")
  }
}

@MainActor
final class MacDurableDraftTests: XCTestCase {
  func testANewSessionRestoresItsProjectAlongWithTheText() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var state = MacFixtures.listState
    state.userId = "new-draft-user"
    let project = try XCTUnwrap(state.catalog.projects.last)
    let source = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    var service = MacComposerFixture.service
    service.drafts = MacDraftStore(root: directory)
    var first: MacNewSessionController? = MacNewSessionController(source: source, service: service)
    let input = try XCTUnwrap(first?.view.descendants(MacComposerTextView.self).first)
    first?.selectProject(project.id)
    input.string = "A task for this project"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    first = nil
    let restored = MacNewSessionController(source: source, service: service)
    let restoredInput = try XCTUnwrap(restored.view.descendants(MacComposerTextView.self).first)
    XCTAssertEqual(restoredInput.string, "A task for this project")
    let heading = try XCTUnwrap(restored.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "new-session-project-heading" })
    XCTAssertTrue(heading.title.contains(project.name))
  }

  func testAMissingRestoredAttachmentMustBeRemovedBeforeSending() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = directory.appendingPathComponent("notes.txt")
    try Data("Notes".utf8).write(to: original)
    var files = MacDraftAttachments()
    _ = files.add(urls: [original])
    let store = MacDraftStore(root: directory.appendingPathComponent("drafts"))
    let scope = MacDraftStore.Scope(user: "u", workspace: "w", session: "s")
    let saved = try store.save(scope, text: "Read this", attachments: files.items, selection: nil, owner: "writer")
    try FileManager.default.removeItem(at: XCTUnwrap(saved.attachments.first?.url))
    let controller = MacComposerController(model: .init(mode: .reply), service: MacComposerFixture.service)
    controller.bindDraft(scope, store: store)
    controller.updateReply(ready: true, capability: nil, choice: nil)
    _ = controller.view
    XCTAssertFalse(controller.model.canSend)
    XCTAssertFalse(controller.model.attachmentNotice.isEmpty)
    controller.removeAttachment(try XCTUnwrap(controller.model.attachments.items.first?.id))
    XCTAssertTrue(controller.model.canSend)
    XCTAssertEqual(controller.model.text, "Read this")
  }

  func testAnAcknowledgementDoesNotClearNewTypingEvenWhenItRepeatsTheSentText() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = MacDraftStore(root: directory)
    let scope = MacDraftStore.Scope(user: "u", workspace: "w", session: "s")
    try store.save(scope, text: "Continue", attachments: [], selection: nil, owner: "window")
    try store.handoff(scope, sendId: "send-one")
    try store.save(scope, text: "Continue", attachments: [], selection: nil, owner: "window")
    try store.complete(scope, sendId: "send-one")
    XCTAssertEqual(try store.load(scope)?.record.text, "Continue")
  }

  func testTheOutboxOwnsSentFilesUntilItsAcknowledgementWhileTheNextDraftStaysIndependent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = directory.appendingPathComponent("notes.txt")
    try Data("Sent file".utf8).write(to: original)
    var files = MacDraftAttachments()
    XCTAssertTrue(files.add(urls: [original]).isEmpty)
    let store = MacDraftStore(root: directory.appendingPathComponent("drafts"))
    let scope = MacDraftStore.Scope(user: "u", workspace: "w", session: "s")
    let saved = try store.save(scope, text: "First", attachments: files.items, selection: nil, owner: "window")
    let sent = try XCTUnwrap(saved.attachments.first?.url)
    try store.handoff(scope, sendId: "first")
    try store.save(scope, text: "Next", attachments: [], selection: nil, owner: "window")
    XCTAssertTrue(FileManager.default.fileExists(atPath: sent.path), "clearing the input must not break an upload")
    try store.complete(scope, sendId: "first")
    XCTAssertFalse(FileManager.default.fileExists(atPath: sent.path))
    XCTAssertEqual(try store.load(scope)?.record.text, "Next")
  }

  func testTwoWindowsOnTheSameScopeObserveTheLatestDraft() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = MacDraftStore(root: directory)
    let scope = MacDraftStore.Scope(user: "u", workspace: "w", session: "s")
    let first = MacComposerController(model: .init(mode: .reply), service: MacComposerFixture.service)
    let second = MacComposerController(model: .init(mode: .reply), service: MacComposerFixture.service)
    first.bindDraft(scope, store: store)
    second.bindDraft(scope, store: store)
    _ = second.view
    let input = try XCTUnwrap(first.view.descendants(MacComposerTextView.self).first)
    input.string = "Shared draft"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    XCTAssertEqual(second.model.text, "Shared draft")
  }

  func testASaveFailureLeavesTheInputInPlaceAndDoesNotSubmitIt() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("not a directory".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var calls = 0
    var service = MacComposerFixture.service
    service.reply = { _, _ in calls += 1 }
    let controller = MacComposerController(model: .init(mode: .reply), service: service)
    controller.bindDraft(.init(user: "u", workspace: "w", session: "s"), store: MacDraftStore(root: file))
    controller.updateReply(ready: true, capability: nil, choice: nil)
    let input = try XCTUnwrap(controller.view.descendants(MacComposerTextView.self).first)
    input.string = "Keep this"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    try XCTUnwrap(controller.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-send" }).performClick(nil)
    XCTAssertEqual(controller.model.text, "Keep this")
    XCTAssertEqual(calls, 0)
    XCTAssertFalse(controller.model.attachmentNotice.isEmpty)
  }

  func testRecreatingAReplyRestoresTextAndItsOwnAttachmentCopyWithoutLeakingToAnotherScope() throws {
    var state = MacFixtures.listState
    state.userId = "draft-\(UUID().uuidString)"
    let id = state.catalog.sessions[0].id
    let sessions = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    try Data("Retain this attachment".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var first: MacReplyBridge? = MacReplyBridge(sessionId: id, sessions: sessions)
    let input = try XCTUnwrap(first?.composer.view.descendants(MacComposerTextView.self).first)
    input.string = "Review the attached notes"
    input.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: input))
    first?.composer.addFiles([file])
    first = nil
    try FileManager.default.removeItem(at: file)
    let restored = MacReplyBridge(sessionId: id, sessions: sessions)
    _ = restored.composer.view
    XCTAssertEqual(restored.composer.model.text, "Review the attached notes")
    let attachment = try XCTUnwrap(restored.composer.model.attachments.items.first)
    XCTAssertEqual(try String(contentsOf: attachment.url, encoding: .utf8), "Retain this attachment")
    state.workspaceId = "other-workspace"
    let other = MacReplyBridge(sessionId: id, sessions: sessions)
    _ = other.composer.view
    XCTAssertEqual(other.composer.model.text, "")
    XCTAssertTrue(other.composer.model.attachments.isEmpty)
  }
}

@MainActor
final class MacWorkspaceChromeTests: XCTestCase {
  func testTabTitlesAndBadgesFollowTheCatalog() {
    let name = Notification.Name("MacWorkspaceChromeTests")
    var state = MacFixtures.listState
    let sessions = MacSessionsSource(changes: [name], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let workspace = MacWorkspaceController(environment: MacEnvironment(
      sessions: sessions, pane: { MacSessionSummaryController(sessionId: $0, sessions: sessions) }, newSession: { MacPlaceholderController(text: "") }
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
    let source = MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in }, selectWorkspace: { selected.append($0) })
    let controller = MainWindowController(environment: MacEnvironment(
      sessions: source, pane: { MacSessionSummaryController(sessionId: $0, sessions: source) },
      newSession: { MacPlaceholderController(text: "") }, requiresAccount: false
    ))
    defer { controller.window?.close() }
    let picker = try XCTUnwrap(controller.workspace?.sidebar.bottomAccessory.view.descendants(NSPopUpButton.self).first)
    XCTAssertFalse(picker.isHidden)
    let menu = try XCTUnwrap(picker.menu)
    let index = try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "w-side" })
    menu.performActionForItem(at: index)
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
