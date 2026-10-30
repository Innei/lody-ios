import AppKit
import LodyCore
import LodyData

@MainActor
final class MacNewSessionController: NSViewController {
  private let composer: MacComposerController
  private let source: MacSessionsSource
  private let status = NSTextField(labelWithString: "")
  private var online: Set<String>
  private var observers: [NSObjectProtocol] = []

  init(source: MacSessionsSource, service: MacComposerService) {
    let state = source.read()
    var model = MacComposerModel(mode: .newSession)
    let projects = Self.projects(state)
    model.form = CreateSessionForm(userId: state.userId, workspaceId: state.workspaceId, projects: projects, machineNames: state.catalog.machineNames)
    model.form.open(projectId: nil, context: projects.isEmpty ? "chat" : nil)
    var wrapped = service
    wrapped.create = { [weak status] draft, payload in
      service.create(draft, payload)
      let title = (payload["text"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
      status?.stringValue = String(localized: "mac.newSession.starting \(title)", bundle: .lodyMac)
    }
    self.source = source
    online = Set(state.presence.onlineMachineIds)
    composer = MacComposerController(model: model, service: wrapped)
    super.init(nibName: nil, bundle: nil)
    observers = source.changes.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.catalogChanged() }
      }
    }
  }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  required init?(coder: NSCoder) { nil }

  private static func projects(_ state: SessionListState) -> [CreateProject] {
    state.catalog.projects.map { CreateProject(id: $0.id, machineId: $0.machineId, name: $0.name, rootPath: $0.rootPath) }
  }

  private func catalogChanged() {
    let state = source.read()
    let next = Set(state.presence.onlineMachineIds)
    composer.updateCatalog(projects: Self.projects(state), machineNames: state.catalog.machineNames, reload: next != online)
    online = next
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
    let heading = NSTextField(labelWithString: String(localized: "mac.newSession.title", bundle: .lodyMac))
    heading.font = .systemFont(ofSize: 22, weight: .semibold)
    heading.translatesAutoresizingMaskIntoConstraints = false
    addChild(composer)
    composer.view.translatesAutoresizingMaskIntoConstraints = false
    status.textColor = .secondaryLabelColor
    status.setAccessibilityIdentifier("new-session-status")
    status.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(heading)
    root.addSubview(composer.view)
    root.addSubview(status)
    NSLayoutConstraint.activate([
      heading.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      heading.bottomAnchor.constraint(equalTo: composer.view.topAnchor, constant: -20),
      composer.view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      composer.view.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 20),
      composer.view.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
      composer.view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).withPriority(.defaultHigh),
      status.topAnchor.constraint(equalTo: composer.view.bottomAnchor, constant: 12),
      status.centerXAnchor.constraint(equalTo: root.centerXAnchor),
    ])
    root.setAccessibilityIdentifier("new-session")
    view = root
  }
}

@MainActor
final class MacLiveSessionPane {
  static func make(sessionId: String) -> MacSessionPane {
    let bridge = MacReplyBridge(sessionId: sessionId, sessions: .live)
    let pane = MacSessionController(
      sessionId: sessionId, source: .live(sessionId: sessionId, state: SessionPublished.state()), composer: bridge.composer
    )
    pane.retained = bridge
    pane.onFeed = { [weak bridge] in bridge?.update($0) }
    pane.onStreaming = { [weak bridge] in bridge?.setStreaming($0) }
    pane.onRetry = { [weak bridge] in bridge?.retry() }
    pane.pendingJSON = { [weak bridge] in bridge?.pendingJSON ?? "" }
    bridge.onPending = { [weak pane] in pane?.refreshPending() }
    return pane
  }
}
