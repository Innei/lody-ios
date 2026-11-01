import AppKit
import LodyCore
import LodyData

@MainActor
final class MacNewSessionController: NSViewController {
  private let composer: MacComposerController
  private let source: MacSessionsSource
  private let status = NSTextField(labelWithString: "")
  private let heading = NSButton()
  private var explicitContext = false
  var onSubmit: (() -> Void)?
  var onChooseProject: (() -> Void)? { didSet { composer.onChooseProject = onChooseProject } }
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
    composer.onSend = { [weak self] in self?.onSubmit?() }
    composer.onProjectChange = { [weak self] userInitiated in
      guard let self else { return }
      if userInitiated { explicitContext = true }
      updateHeading()
    }
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

  func inherit(projectId: String?, machineId: String?) {
    guard !composer.hasDraft, !explicitContext, let projectId else { return }
    composer.selectProject(projectId, machineId: machineId, userInitiated: false)
  }

  func focusInput() { composer.focusInput() }

  func selectProject(_ id: String?) { composer.selectProject(id); focusInput() }

  @objc private func chooseProject() { composer.showProjects() }

  private func updateHeading() {
    let form = composer.model.form
    let name = composer.model.projectName
    if !form.chat, let name {
      heading.title = String(localized: "mac.newSession.projectPrompt \(name)", bundle: .lodyMac)
    } else {
      heading.title = String(localized: "mac.newSession.chatPrompt", bundle: .lodyMac)
    }
    let title = NSMutableAttributedString(string: heading.title, attributes: [
      .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.labelColor,
    ])
    if !form.chat, let name, let range = heading.title.range(of: name) {
      title.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, range: NSRange(range, in: heading.title))
    }
    heading.attributedTitle = title
  }

  private static func projects(_ state: SessionListState) -> [CreateProject] {
    state.catalog.projects.map { CreateProject(id: $0.id, machineId: $0.machineId, name: $0.name, rootPath: $0.rootPath) }
  }

  private func catalogChanged() {
    let state = source.read()
    let next = Set(state.presence.onlineMachineIds)
    composer.updateCatalog(projects: Self.projects(state), machineNames: state.catalog.machineNames, reload: next != online)
    online = next
    updateHeading()
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
    heading.isBordered = false
    heading.font = .systemFont(ofSize: 22, weight: .medium)
    heading.cell?.lineBreakMode = .byTruncatingMiddle
    heading.target = self
    heading.action = #selector(chooseProject)
    heading.setAccessibilityIdentifier("new-session-project-heading")
    let mark = NSImageView(image: NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage())
    mark.contentTintColor = .tertiaryLabelColor
    mark.symbolConfiguration = .init(pointSize: 32, weight: .regular)
    mark.setAccessibilityElement(false)
    let introduction = NSStackView(views: [mark, heading])
    introduction.orientation = .vertical
    introduction.alignment = .centerX
    introduction.spacing = 20
    introduction.translatesAutoresizingMaskIntoConstraints = false
    addChild(composer)
    composer.view.translatesAutoresizingMaskIntoConstraints = false
    status.textColor = .secondaryLabelColor
    status.setAccessibilityIdentifier("new-session-status")
    status.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(introduction)
    root.addSubview(composer.view)
    root.addSubview(status)
    NSLayoutConstraint.activate([
      introduction.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      introduction.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -64),
      introduction.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -48),
      introduction.bottomAnchor.constraint(lessThanOrEqualTo: composer.view.topAnchor, constant: -24),
      composer.view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      composer.view.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -20),
      composer.view.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
      composer.view.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -48),
      composer.view.widthAnchor.constraint(equalToConstant: 680).withPriority(.init(249)),
      status.bottomAnchor.constraint(equalTo: composer.view.topAnchor, constant: -12),
      status.centerXAnchor.constraint(equalTo: root.centerXAnchor),
    ])
    root.setAccessibilityIdentifier("new-session")
    view = root
    updateHeading()
  }
}
