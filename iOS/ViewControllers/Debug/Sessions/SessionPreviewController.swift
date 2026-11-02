import LodyCore
import UIKit

@MainActor
final class SessionPreviewController: SessionController {
  private let fixture: SessionPreviewFixture
  private let probe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
  private var presentations: NSObjectProtocol?
  private var streamTimer: Timer?
  private var streamFailures = Set<String>()
  private var streamPhases = Set<String>()
  private var sawPacing = false
  private var sawFade = false

  init(scenario: String) {
    let fixture = SessionPreviewFixture(offline: scenario == "offline", tasks: scenario == "tasks", restore: scenario == "stream-restore")
    self.fixture = fixture
    var environment = SessionSendEnvironment.live
    environment.composer = SessionComposerService(options: { _, _ in
      let models = [CapabilityChoice(id: "agent-model", name: "Agent Model"), CapabilityChoice(id: "alternate", name: "Alternate Model")]
      return CreationOptions(sessionId: SessionPreviewFixture.sessionId, agents: [], capabilities: [
        Capability(machineId: "preview-mac", cliType: "builtin", agentType: "codex", models: models,
          reasoningEfforts: ["agent-model": ["low", "medium", "high"], "alternate": ["low", "medium", "high"]], configOptions: [
            ConfigOption(id: "model", name: "Model", category: "model", type: "select", currentValue: .string("agent-model"), options: models),
            ConfigOption(id: "reasoning_effort", name: "Effort", category: "thought_level", type: "select", currentValue: .string("medium"), options: ["low", "medium", "high"].map { CapabilityChoice(id: $0, name: $0) }),
          ]),
      ])
    }, tier: { _, _ in nil })
    super.init(
      sessionId: SessionPreviewFixture.sessionId, findQuery: scenario == "find" ? "needle" : "",
      source: SessionSource(
        changes: [SessionPreviewFixture.change], read: { fixture.state },
        write: { _, id, write in try await fixture.write(id, write) }
      ),
      feed: SessionFeedService(
        watch: { _, receive in fixture.watch(receive) },
        reconnect: { _ in fixture.reconnect() },
        cached: { _, _, _ in
          if fixture.restore { return nil }
          return SessionPreviewFixture.envelope(status: "syncing", revision: 0, reply: "Cached reply", tasks: fixture.tasks)
        }
      ),
      environment: environment,
      itemDetail: ItemDetailService(load: { params in
        .init(itemId: params.itemId, rev: 1, blocks: [.object([
          "type": .string("terminal_output"), "output": .string("Session tool detail"),
        ])], truncated: false)
      }, observe: { _ in {} }),
      simulator: .init(call: { command in
        if case .stop = command { return .init(success: true) }
        if case .list = command {
          return .init(success: true, devices: [.init(udid: "native-fixture-phone", name: "Fixture Phone", runtime: "iOS 27", deviceType: "iPhone", state: "Booted", available: true, occupancy: .available)])
        }
        return .init(success: true, preview: .init(operationId: "native-fixture", udid: "native-fixture-phone", phase: .ready, transport: .remote, viewerUrl: "lody-simulator-fixture://stream"))
      }),
      pullRequest: { _, _ in PullRequestPreviewController(params: [:]) },
      browser: { _, _ in .init(url: "https://native-fixture.trycloudflare.com") }
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    streamTimer?.invalidate()
    if let presentations { NotificationCenter.default.removeObserver(presentations) }
  }

  override var persistsDraft: Bool { false }

  override func viewDidLoad() {
    probe.isAccessibilityElement = true
    probe.accessibilityIdentifier = "session-preview-probe"
    super.viewDidLoad()
    view.addSubview(probe)
    fixture.changed = { [weak self] in self?.updateProbe() }
    presentations = NotificationCenter.default.addObserver(forName: Notification.Name("LodyWillPresent"), object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.fixture.record("present") }
    }
    updateProbe()
    if fixture.restore {
      streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateProbe() }
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    configureStreamActions()
  }

  override func render() {
    super.render()
    if isViewLoaded { configureStreamActions() }
  }

  private func configureStreamActions() {
    guard fixture.restore else { return }
    LodyNavigationHeader.of(navigationItem).rightItems = [
      UIBarButtonItem(title: "Append", primaryAction: UIAction { [weak self] _ in self?.fixture.append() }),
      UIBarButtonItem(title: "Catch up", primaryAction: UIAction { [weak self] _ in self?.feed?.reconnect() }),
    ]
  }

  override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
    fixture.record("present")
    super.present(controller, animated: animated, completion: completion)
  }

  private func updateProbe() {
    if fixture.restore {
      let phase = fixture.phase
      if chat.transcript.entries.last?.items.last?.text == phase,
         let tail = chat.rows["restore:tail"] {
        streamPhases.insert(phase)
        for (id, text) in [("first", SessionPreviewFixture.first), ("middle", SessionPreviewFixture.middle)] {
          if chat.rows["restore:" + id]?.text != text { streamFailures.insert(phase + ":" + id) }
          if chat.store.isAnimating(id: "restore:" + id) { streamFailures.insert(phase + ":" + id + ":fade") }
        }
        if phase == "live" {
          sawPacing = sawPacing || (tail.text.count > SessionPreviewFixture.initialTail.count && tail.text.count < fixture.tail.count)
          sawFade = sawFade || chat.store.isAnimating(id: tail.id)
        } else if tail.text != fixture.tail || chat.store.isAnimating(id: tail.id) {
          streamFailures.insert(phase + ":tail")
        }
      }
      let value: [String: Any] = ["phase": phase, "seen": streamPhases.sorted(), "failures": streamFailures.sorted(),
        "paced": sawPacing, "faded": sawFade]
      probe.accessibilityValue = String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
      return
    }
    probe.accessibilityValue = fixture.log.joined(separator: ",")
  }
}

@MainActor
private final class SessionPreviewFixture {
  static let change = Notification.Name("LodySessionPreviewFixture")
  static let sessionId = "native-session"
  private(set) var log: [String] = []
  var changed: (() -> Void)?
  private let offline: Bool
  let tasks: Bool
  let restore: Bool
  private(set) var phase = "restore"
  private(set) var tail = initialTail
  static let first = "I checked the current implementation. This paragraph is complete and should stay visible."
  static let middle = "The first check passed. This second paragraph is also complete while the agent keeps working."
  static let initialTail = "I am now checking the remaining behavior."
  private var catalog: SessionCatalog
  private var receive: (@MainActor (SessionRuntimeEvent) -> Void)?
  private var revision = 1

  init(offline: Bool, tasks: Bool, restore: Bool = false, now: Double = LodyRelativeTime.now()) {
    self.offline = offline
    self.tasks = tasks
    self.restore = restore
    catalog = SessionCatalog(
      projects: [SessionProject(id: "preview-lody", name: "Lody", rootPath: "/Users/preview/lody")],
      sessions: [
        SessionItem(
          id: Self.sessionId, title: "Session preview", status: "idle", projectId: "preview-lody",
          lastMessageAt: now - 60_000, branchName: "feature/native-session", machineId: "preview-mac", cliType: "builtin", agentType: "codex",
          pullRequests: [.init(repository: "Innei/lody-ios", number: 31, status: "open", ci: "f")]
        ),
      ],
      machineIds: ["preview-mac"], machineNames: ["preview-mac": "Preview Mac"], machineSimulators: ["preview-mac": "available"]
    )
  }

  var state: SessionListState {
    SessionListState(
      userId: "preview-user", workspaceId: "preview-workspace",
      presence: SettingsMachinePresence(state: "live", onlineMachineIds: ["preview-mac"]),
      workspaces: [AuthWorkspace(id: "preview-workspace", name: "Preview", slug: "preview", image: nil)], catalog: catalog
    )
  }

  func watch(_ receive: @escaping @MainActor (SessionRuntimeEvent) -> Void) -> @MainActor () -> Void {
    self.receive = receive
    record("watch")
    if restore {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.emitRestoration() }
    } else { emit() }
    return { [weak self] in
      self?.receive = nil
      self?.record("unwatch")
    }
  }

  func reconnect() {
    record("reconnect")
    revision += 1
    if restore {
      phase = "catchup"
      tail += " Changes received while away appear immediately."
      emitRestoration()
    } else { emit(forceLive: true) }
  }

  func append() {
    phase = "live"
    tail += " Only these newly arriving words should stream into view."
    revision += 1
    emitRestoration()
  }

  private func emitRestoration() {
    let object: [String: Any] = ["v": 1, "status": "live", "revision": revision, "entries": [
      ["id": "restore", "role": "assistant", "status": "running", "finished": false, "items": [
        ["itemId": "first", "type": "text", "text": Self.first],
        ["itemId": "tool-one", "type": "tool_call", "status": "completed", "title": "Read file"],
        ["itemId": "middle", "type": "text", "text": Self.middle],
        ["itemId": "tool-two", "type": "tool_call", "status": "completed", "title": "Run checks"],
        ["itemId": "tail", "type": "text", "text": tail],
        ["itemId": "phase", "type": "system_notice", "skipTranscript": true, "text": phase],
      ]],
    ]]
    let session = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    receive?(.init(generation: 1, state: "live", sessionId: Self.sessionId, session: session))
    record(phase)
  }

  func write(_ id: String, _ change: SessionWrite) async throws {
    guard let index = catalog.sessions.firstIndex(where: { $0.id == id }) else { return }
    switch change {
    case .archive(let archived):
      catalog.sessions[index].archived = archived
      record(archived ? "archive" : "unarchive")
    case .rename(let title):
      catalog.sessions[index].title = title
      record("rename")
    case .delete:
      try await Task.sleep(for: .milliseconds(300))
      catalog.sessions.removeAll { $0.id == id }
      record("delete")
    case .pin, .read:
      return
    }
    NotificationCenter.default.post(name: Self.change, object: nil)
  }

  private func emit(forceLive: Bool = false) {
    let status = offline && !forceLive ? "offline" : "live"
    let session = Self.envelope(status: status, revision: revision, reply: "Live reply with a needle", tasks: tasks)
    // Deliver after the cached frame, the way the runtime answers an open.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let receive = self.receive else { return }
        if status == "offline" {
          receive(SessionRuntimeEvent(generation: 1, state: "failed"))
        } else {
          receive(SessionRuntimeEvent(generation: 1, state: "live", sessionId: Self.sessionId, session: session))
        }
        self.record(status)
        if self.tasks, status == "live" { self.stream(phase: 1) }
      }
    }
  }

  private func stream(phase: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let receive = self.receive else { return }
        self.revision += 1
        let session = Self.envelope(status: "live", revision: self.revision, reply: "Live reply with a needle", tasks: true, phase: phase)
        receive(SessionRuntimeEvent(generation: 1, state: "live", sessionId: Self.sessionId, session: session))
        self.record(phase == 1 ? "streaming" : "settled")
        if phase == 1 { self.stream(phase: 2) }
      }
    }
  }

  func record(_ entry: String) {
    log.append(entry)
    changed?()
  }

  nonisolated static func envelope(status: String, revision: Int, reply: String, tasks: Bool, phase: Int = 0) -> String? {
    var plan: [[String: Any]] = []
    if phase == 1 { plan = [["itemId": "plan", "type": "text", "text": "Wrote the plan to [plan.md](docs/pl"]] }
    if phase == 2 { plan = [["itemId": "plan", "type": "text", "text": "Wrote the plan to [plan.md](docs/plan.md)."]] }
    let answer = tasks ? reply + "\n\nUpdated [App.tsx](src/App.tsx) and [notes.md](docs/notes.md#L3).\n\n```swift\nlet session = SessionPreview()\n```" : reply
    let working: [[String: Any]] = [
      [
        "id": "preview-follow-up", "role": "user", "status": "completed", "finished": true, "timestamp": "2026-10-29T10:02:00Z",
        "items": [
          ["itemId": "text", "type": "text", "text": "Run the checks again on @src/App.tsx"],
          ["itemId": "attachment", "type": "file", "file": ["id": "fixture-attachment", "fileName": "checks.txt"]],
        ],
      ],
      [
        "id": "preview-working", "role": "assistant", "status": phase == 2 ? "completed" : "in_progress", "finished": phase == 2,
        "items": [
          ["itemId": "report", "type": "file", "file": ["id": "fixture-report", "fileName": "report.txt"]],
        ] + plan + [
          ["itemId": "running-task", "type": "subagent_task", "taskId": "native-running-task", "status": "in_progress",
           "actor": "test-runner", "description": "Run the native checks"],
        ],
      ],
    ]
    let object: [String: Any] = [
      "v": 1, "status": status, "revision": revision,
      "preview": ["label": "localhost:5173", "active": true],
      "entries": [
        [
          "id": "preview-user", "role": "user", "status": "completed", "finished": true, "timestamp": "2026-10-29T10:00:00Z",
          "items": [["itemId": "text", "type": "text", "text": "Show the native session page"]],
        ],
        [
          "id": "preview-answer", "role": "assistant", "status": "completed", "finished": true, "endedAt": 1_793_268_064_000,
          "modelInfo": ["name": "Fixture model", "thoughtLevel": "High"],
          "fileDiffs": tasks ? [
            ["path": "src/App.tsx", "add": 3, "del": 1],
            ["path": "docs/notes.md", "add": 12, "del": 0],
            ["path": "packages/cloud-runtime/src/replica.ts", "add": 18, "del": 6],
          ] : [],
          "items": [
            ["itemId": "edit", "rev": 1, "hasDetail": true, "type": "tool_call", "kind": "edit", "status": "completed", "title": "Edit", "path": "src/App.tsx",
             "added": 3, "removed": 1],
            ["itemId": "task", "type": "subagent_task", "taskId": "native-task", "status": "completed",
             "actor": "test-runner", "description": "Verify the native session", "summary": "Task summary: all checks passed."],
            ["itemId": "reply", "type": "text", "text": answer],
          ],
        ],
      ] + (tasks ? working : []),
    ]
    return (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) }
  }
}
