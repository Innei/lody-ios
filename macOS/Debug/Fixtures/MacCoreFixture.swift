#if DEBUG
import AppKit
import LodyCore
import LodyData

/// Deterministic service boundaries; every visible control is a production controller.
@MainActor
final class MacCoreFixture {
  private var changed: (@MainActor (SessionFeedState) -> Void)?
  private var answered = false
  private var running = true
  private var steered = false
  private var retryCount = 0
  private var version = 1
  private var queue: [RuntimeContract.SessionQueueItem] = [
    .init(id: "q-one", revision: "1", messageId: "next-one", text: "Add keyboard navigation", attachments: ["notes.txt"], editing: false),
    .init(id: "q-two", revision: "1", messageId: "next-two", text: "Review the native sidebar", attachments: [], editing: false),
    .init(id: "q-three", revision: "1", messageId: "next-three", text: "Run the focused checks", attachments: [], editing: false),
  ]
  private var catalog = MacFixtures.listState
  private var bridge: MacReplyBridge?

  static func controller() -> NSViewController {
    let fixture = MacCoreFixture()
    var state = MacFixtures.listState
    state.userId = "u-core-fixture"
    state.catalog.sessions[0].cliType = "builtin"
    fixture.catalog = state
    let sessions = MacSessionsSource(changes: [], read: { fixture.catalog }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let sender = SessionSender(sessionId: "s-mac", store: nil, services: OutboxSession.shared.services, inflight: OutboxInflight())
    let bridge = MacReplyBridge(sessionId: "s-mac", sessions: sessions, controlRequest: { [fixture] payload in
      try await Task.sleep(for: .milliseconds(180))
      let body = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
      if body?["action"] as? String == "stop" {
        fixture.running = false
        fixture.catalog.catalog.sessions[0].status = "idle"
      }
      else {
        fixture.steered = true
        fixture.queue.removeAll { $0.messageId == body?["messageId"] as? String }
      }
      fixture.publish()
      return fixture.running ? #"{"state":"applied"}"# : #"{"state":"stopped"}"#
    }, sender: sender, composerService: .init(options: { _, _ in
      var capability = MacComposerFixture.capability
      capability.steer = true
      return CreationOptions(sessionId: "s-mac", agents: [], capabilities: [capability])
    }, tier: { _, _ in nil }))
    fixture.bridge = bridge
    let pane = MacSessionController(sessionId: "s-mac", source: fixture.source, composer: bridge.composer)
    pane.retained = fixture
    pane.onFeed = { [weak bridge] in bridge?.update($0) }
    pane.onSteer = { [weak bridge] in bridge?.controlTurn("steer", messageId: $0) }
    _ = pane.view
    pane.setStreaming(true)
    return pane
  }

  private var source: MacTranscriptSource {
    MacTranscriptSource(start: { [self] receive in changed = receive; publish() }, stop: { [self] in changed = nil }, detail: { _ in nil }, respond: { _, _ in .accepted }, respondQuestions: { [self] _, _, answers in
      guard answers["targets"] != nil, answers["notes"] != nil else { return .stale }
      answered = true
      publish()
      return .accepted
    }, queueService: MacQueueService(request: { [self] in try await queueRequest($0) }), diffService: MacDiffService(diff: { [self] request in
      if request.path == "Retry.swift" {
        retryCount += 1
        if retryCount == 1 { throw OutboxError.scopeExpired }
      }
      if request.path == "Icon.png" {
        return .ok(.init(base: .current, path: request.path, old: .init(kind: .binary), new: .init(kind: .binary)))
      }
      return .ok(.init(base: request.entryId == nil ? .current : .turn, path: request.path,
                       old: .init(kind: .text, text: "import AppKit\n\nfunc title() -> String {\n  return \"Lody\"\n}\n"),
                       new: .init(kind: .text, text: "import AppKit\n\nfunc title() -> String {\n  return \"Lody for Mac\"\n}\n")))
    }, changes: { _ in .ok(.init(base: "main", files: [.init(path: "Sources/App.swift", add: 1, del: 1), .init(path: "Retry.swift", add: 1, del: 1), .init(path: "Icon.png")])) }), userId: "u-core-fixture")
  }

  private func queueRequest(_ params: RuntimeContract.SessionQueueParams) async throws -> RuntimeContract.SessionQueueResult {
    let id: String
    switch params {
    case .list: return .init(state: .ready, items: queue)
    case .begin(let p):
      id = p.id
      if let i = queue.firstIndex(where: { $0.id == id }) { queue[i].editing = true; queue[i].editToken = p.editToken }
    case .save(let p):
      id = p.id
      if let i = queue.firstIndex(where: { $0.id == id }) { queue[i].text = p.text; queue[i].editing = false; queue[i].editToken = nil }
    case .cancel(let p):
      id = p.id
      if let i = queue.firstIndex(where: { $0.id == id }) { queue[i].editing = false; queue[i].editToken = nil }
    case .remove(let p): id = p.id; queue.removeAll { $0.id == id }
    case .move(let p):
      id = p.id
      if let from = queue.firstIndex(where: { $0.id == id }), let to = queue.firstIndex(where: { $0.id == p.overId }) { let item = queue.remove(at: from); queue.insert(item, at: to) }
    }
    version += 1
    if let i = queue.firstIndex(where: { $0.id == id }) { queue[i].revision = String(version) }
    publish()
    return .init(state: .ready, items: queue)
  }

  private func publish() {
    var items: [[String: Any]] = [
      ["itemId": "intro", "type": "text", "text": steered ? "Steering accepted. Continuing with the queued message." : "The native window title is updated. Choose the next verification targets."],
      ["itemId": "edit", "type": "tool_call", "kind": "edit", "title": "Update App.swift", "status": "completed", "path": "Sources/App.swift", "added": 1, "removed": 1],
    ]
    if !answered {
      items.append(["itemId": "question", "type": "tool_call", "kind": "ask_user_question", "title": "Verify the Mac client", "permission": [
        "pending": true, "requestId": "core-question", "options": [["optionId": "allow", "name": "Continue", "kind": "allow_once"]],
        "questionMeta": ["allowCustomAnswer": true, "questions": [
          ["id": "targets", "header": "Targets", "question": "Which platforms should we verify?", "multiSelect": true, "options": [["label": "macOS", "description": "Run the native Mac checks"], ["label": "iOS", "description": "Verify shared data behavior"]]],
          ["id": "notes", "header": "Notes", "question": "Any notes for the verification?", "multiSelect": false, "options": []],
        ]],
      ]])
    } else { items.append(["itemId": "answer", "type": "text", "text": "Answers received. Running the selected checks."]) }
    var entries: [[String: Any]] = [
      ["id": "u-core", "role": "user", "finished": true, "status": "completed", "items": [["itemId": "text", "type": "text", "text": "Update the Mac window title and verify the changes."]]],
      ["id": "core-diff", "role": "assistant", "finished": true, "status": "completed", "items": [["itemId": "edit", "type": "tool_call", "kind": "edit", "title": "Update App.swift", "status": "completed", "path": "Sources/App.swift", "added": 1, "removed": 1]], "fileDiffs": [["path": "Sources/App.swift", "add": 1, "del": 1]]],
      ["id": "core-turn", "role": "assistant", "finished": !running, "status": running ? "running" : "completed", "items": items],
    ]
    entries += queue.map { ["id": $0.messageId ?? $0.id, "role": "user", "status": "queued", "finished": false, "items": [["itemId": "text", "type": "text", "text": $0.text]]] }
    var feed = SessionFeedState(status: "live", entriesJSON: String(decoding: (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8), as: UTF8.self))
    feed.transcript.unfinishedTurnId = running ? "core-turn" : nil
    feed.transcript.entryIds = Set(entries.compactMap { $0["id"] as? String })
    changed?(feed)
  }
}

@MainActor
final class MacCoreDraftController: NSViewController {
  private let store = MacDraftStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("lody-draft-scene-\(UUID().uuidString)"))
  private var composer: MacComposerController?
  private var session = "draft-one"
  private let body = NSView()
  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 480))
    let title = NSTextField(labelWithString: "Drafts stay with their conversation")
    title.font = .preferredFont(forTextStyle: .title2)
    let tabs = NSStackView(views: [
      MacActionButton(title: "Draft session") { [weak self] in self?.show("draft-one") },
      MacActionButton(title: "Another session") { [weak self] in self?.show("draft-two") },
      MacActionButton(title: "Reopen composer") { [weak self] in guard let self else { return }; show(session) },
    ])
    let stack = NSStackView(views: [title, tabs, body])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
      body.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    view = root
    show(session)
  }
  private func show(_ session: String) {
    self.session = session
    composer?.view.removeFromSuperview()
    composer?.removeFromParent()
    var model = MacComposerModel(mode: .reply)
    model.replyReady = true
    let service = MacComposerService(options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in }, pick: { _, picked in picked(MacComposerFixture.pickedFiles()) })
    let next = MacComposerController(model: model, service: service)
    next.bindDraft(.init(user: "fixture", workspace: "fixture", session: session), store: store)
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.leadingAnchor.constraint(equalTo: body.leadingAnchor), next.view.trailingAnchor.constraint(equalTo: body.trailingAnchor), next.view.bottomAnchor.constraint(equalTo: body.bottomAnchor), next.view.topAnchor.constraint(greaterThanOrEqualTo: body.topAnchor),
    ])
    composer = next
  }
}
#endif
