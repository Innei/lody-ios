import LodyCore
import UIKit

@MainActor
final class SessionPreviewController: SessionController {
  private let fixture: SessionPreviewFixture
  private let probe = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

  init(scenario: String) {
    let fixture = SessionPreviewFixture(offline: scenario == "offline")
    self.fixture = fixture
    super.init(
      sessionId: SessionPreviewFixture.sessionId, findQuery: scenario == "find" ? "needle" : "",
      source: SessionSource(
        changes: [SessionPreviewFixture.change], read: { fixture.state },
        write: { _, id, write in try await fixture.write(id, write) }
      ),
      feed: SessionFeedService(
        watch: { _, receive in fixture.watch(receive) },
        reconnect: { _ in fixture.reconnect() },
        cached: { _, _, _ in SessionPreviewFixture.envelope(status: "syncing", revision: 0, reply: "Cached reply") }
      ),
      itemDetail: ItemDetailService(load: { params in
        .init(itemId: params.itemId, rev: 1, blocks: [.object([
          "type": .string("terminal_output"), "output": .string("Native session tool detail"),
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

  override var persistsDraft: Bool { false }

  override func viewDidLoad() {
    probe.isAccessibilityElement = true
    probe.accessibilityIdentifier = "session-preview-probe"
    super.viewDidLoad()
    view.addSubview(probe)
    fixture.changed = { [weak self] in self?.updateProbe() }
    updateProbe()
  }

  private func updateProbe() {
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
  private var catalog: SessionCatalog
  private var receive: (@MainActor (SessionRuntimeEvent) -> Void)?
  private var revision = 1

  init(offline: Bool, now: Double = LodyRelativeTime.now()) {
    self.offline = offline
    catalog = SessionCatalog(
      projects: [SessionProject(id: "preview-lody", name: "Lody", rootPath: "/Users/preview/lody")],
      sessions: [
        SessionItem(
          id: Self.sessionId, title: "Native session preview", status: "idle", projectId: "preview-lody",
          lastMessageAt: now - 60_000, branchName: "feature/native-session", machineId: "preview-mac",
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
    emit()
    return { [weak self] in
      self?.receive = nil
      self?.record("unwatch")
    }
  }

  func reconnect() {
    record("reconnect")
    revision += 1
    emit(forceLive: true)
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
    let session = Self.envelope(status: status, revision: revision, reply: "Live reply with a needle")
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
      }
    }
  }

  private func record(_ entry: String) {
    log.append(entry)
    changed?()
  }

  nonisolated static func envelope(status: String, revision: Int, reply: String) -> String? {
    let object: [String: Any] = [
      "v": 1, "status": status, "revision": revision,
      "preview": ["label": "localhost:5173", "active": true],
      "entries": [
        [
          "id": "preview-user", "role": "user", "status": "completed", "finished": true,
          "items": [["itemId": "text", "type": "text", "text": "Show the native session page"]],
        ],
        [
          "id": "preview-answer", "role": "assistant", "status": "completed", "finished": true,
          "modelInfo": ["name": "Native fixture model", "thoughtLevel": "High"],
          "items": [
            ["itemId": "edit", "rev": 1, "hasDetail": true, "type": "tool_call", "kind": "edit", "status": "completed", "title": "Edit", "path": "src/App.tsx",
             "added": 3, "removed": 1],
            ["itemId": "task", "type": "subagent_task", "taskId": "native-task", "status": "completed",
             "actor": "test-runner", "description": "Verify the native session", "summary": "Native task summary: all checks passed."],
            ["itemId": "reply", "type": "text", "text": reply],
          ],
        ],
      ],
    ]
    return (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) }
  }
}
