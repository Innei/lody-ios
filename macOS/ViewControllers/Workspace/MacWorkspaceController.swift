import AppKit
import LodyData

@MainActor
final class MacWorkspaceController: NSSplitViewController, MacStreamingTab {
  let environment: MacEnvironment
  let sidebar: SidebarViewController
  private let detail = MacDetailController()
  private var pane: MacSessionPane?
  private var newSession: NSViewController?
  private var scope: [String]
  private var palette: MacPaletteWindowController?
  private var streaming = false
  private var sizedSidebar = false
  private var observers: [NSObjectProtocol] = []
  private(set) var sessionId: String?
  private(set) lazy var actions = MacSessionActions(source: environment.sessions, prompts: .live { [weak self] in self?.view.window })
  var isOnScreen: Bool {
    guard let window = view.window else { return false }
    return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
  }
  var onTitle: ((_ title: String, _ subtitle: String) -> Void)?
  var onBadge: ((MacTabBadge?) -> Void)?
  var onNewSession: (() -> Void)?

  init(environment: MacEnvironment) {
    self.environment = environment
    let state = environment.sessions.read()
    scope = [state.userId, state.workspaceId]
    sidebar = SidebarViewController(source: environment.sessions, account: environment.account)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    palette?.dismiss(restoreFocus: false)
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let side = NSSplitViewItem(sidebarWithViewController: sidebar)
    side.minimumThickness = 280
    side.maximumThickness = 380
    side.preferredThicknessFraction = 320 / 1100
    side.canCollapse = true
    side.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
    side.addTopAlignedAccessoryViewController(sidebar.topAccessory)
    side.addBottomAlignedAccessoryViewController(sidebar.bottomAccessory)
    addSplitViewItem(side)
    let content = NSSplitViewItem(viewController: detail)
    content.minimumThickness = 420
    content.automaticallyAdjustsSafeAreaInsets = true
    addSplitViewItem(content)
    sidebar.onSelect = { [weak self] id in self?.open(id) }
    observers.append(NotificationCenter.default.addObserver(forName: .lodyMacOpenSession, object: nil, queue: .main) { [weak self] note in
      let id = note.userInfo?["sessionId"] as? String
      MainActor.assumeIsolated {
        guard let self, self.view.window?.isKeyWindow == true, let id else { return }
        self.open(id)
      }
    })
    for name in environment.sessions.changes {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.catalogChanged() }
      })
    }
    sidebar.onNewSession = { [weak self] in self?.onNewSession?() }
    sidebar.onSearch = { [weak self] in self?.findSessions(nil) }
    sidebar.onShowSettings = environment.showSettings
    sidebar.actions = actions
    sidebar.onAction = { [weak self] action, id in self?.run(action, id) }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard !sizedSidebar, view.window != nil, splitView.bounds.width >= 760 else { return }
    sizedSidebar = true
    splitView.setPosition(320, ofDividerAt: 0)
  }

  private func run(_ action: MacSessionAction, _ id: String?) {
    Task { await actions.perform(action, sessionId: id) }
  }

  @objc func performSessionAction(_ sender: NSMenuItem) {
    guard let action = (sender.representedObject as? String).flatMap(MacSessionAction.init(rawValue:)) else { return }
    run(action, sessionId)
  }

  @objc func selectPreviousSession(_ sender: Any?) { step(-1) }

  @objc func selectNextSession(_ sender: Any?) { step(1) }
  @objc func findSessions(_ sender: Any?) { showPalette(mode: .search) }

  private func showPalette(mode: MacPaletteModel.Mode, draft: MacNewSessionController? = nil) {
    guard let window = view.window else { return }
    palette?.dismiss(restoreFocus: false)
    let next = MacPaletteWindowController(source: environment.sessions, mode: mode, parent: window) { [weak self, weak draft] destination in
      guard let self else { return }
      switch destination {
      case .chat(let id): open(id)
      case .newChat: open(nil)
      case .manageProjects: environment.showSettings(.projects)
      case .project(let id):
        if let draft { draft.selectProject(id) }
        else { open(nil); (newSession as? MacNewSessionController)?.selectProject(id) }
      }
    }
    palette = next
    next.onDismiss = { [weak self, weak next] in
      if self?.palette === next { self?.palette = nil }
    }
    next.present()
  }

  private func step(_ offset: Int) {
    guard let next = sidebar.neighbor(of: sessionId, step: offset) else { return }
    open(next)
  }

  func open(_ id: String?) {
    guard id != sessionId || pane == nil else { return }
    let context = sessionId.flatMap { environment.sessions.read().catalog.session($0) }
    pane?.setStreaming(false)
    sessionId = id
    sidebar.select(sessionId: id)
    guard let id else {
      pane = nil
      let controller = newSession ?? environment.newSession()
      newSession = controller
      if let draft = controller as? MacNewSessionController {
        draft.onChooseProject = { [weak self, weak draft] in
          guard let draft else { return }
          self?.showPalette(mode: .projects, draft: draft)
        }
        draft.inherit(projectId: context?.projectId, machineId: context?.machineId)
        draft.onSubmit = { [weak self, weak draft] in
          if self?.newSession === draft { self?.newSession = nil }
        }
      }
      detail.show(controller)
      (controller as? MacNewSessionController)?.focusInput()
      onTitle?(String(localized: "mac.newSession.title", bundle: .lodyMac), "")
      onBadge?(nil)
      return
    }
    let next = environment.pane(id)
    pane = next
    detail.show(next)
    next.setStreaming(streaming)
    refreshChrome()
  }

  private func catalogChanged() {
    let state = environment.sessions.read()
    let next = [state.userId, state.workspaceId]
    if next != scope {
      palette?.dismiss(restoreFocus: false)
      scope = next
      newSession = nil
      pane?.setStreaming(false)
      pane = nil
      sessionId = nil
      open(nil)
      return
    }
    refreshChrome()
  }

  private func refreshChrome() {
    guard let sessionId else { return }
    let state = environment.sessions.read()
    let session = state.catalog.session(sessionId)
    let project = state.catalog.projects.first { $0.id == session?.projectId }?.name ?? ""
    onTitle?(session?.title ?? "Lody", project)
    onBadge?(MacTabBadge(session))
  }

  func setStreaming(_ on: Bool) {
    streaming = on
    pane?.setStreaming(on)
  }
}

extension MacWorkspaceController: NSMenuItemValidation {
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(performSessionAction(_:)):
      guard let action = (item.representedObject as? String).flatMap(MacSessionAction.init(rawValue:)) else { return false }
      item.title = actions.title(action, sessionId: sessionId)
      return actions.isEnabled(action, sessionId: sessionId)
    case #selector(selectPreviousSession(_:)):
      return sidebar.neighbor(of: sessionId, step: -1) != nil
    case #selector(selectNextSession(_:)):
      return sidebar.neighbor(of: sessionId, step: 1) != nil
    default:
      return true
    }
  }
}
