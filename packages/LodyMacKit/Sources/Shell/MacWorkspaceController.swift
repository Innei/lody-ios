import AppKit
import LodyData

@MainActor
final class MacWorkspaceController: NSSplitViewController, MacStreamingTab {
  let environment: MacEnvironment
  let sidebar: SidebarViewController
  private let detail = MacDetailController()
  private var pane: MacSessionPane?
  private var streaming = false
  private var observers: [NSObjectProtocol] = []
  private(set) var sessionId: String?
  var onTitle: ((_ title: String, _ subtitle: String) -> Void)?
  var onBadge: ((MacTabBadge?) -> Void)?
  var onNewSession: (() -> Void)?

  init(environment: MacEnvironment) {
    self.environment = environment
    sidebar = SidebarViewController(source: environment.sessions)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let side = NSSplitViewItem(sidebarWithViewController: sidebar)
    side.minimumThickness = 220
    side.maximumThickness = 380
    side.canCollapse = true
    addSplitViewItem(side)
    let content = NSSplitViewItem(viewController: detail)
    content.minimumThickness = 420
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
        MainActor.assumeIsolated { self?.refreshChrome() }
      })
    }
    sidebar.onNewSession = { [weak self] in self?.onNewSession?() }
  }

  func open(_ id: String?) {
    guard id != sessionId || pane == nil else { return }
    pane?.setStreaming(false)
    sessionId = id
    sidebar.select(sessionId: id)
    guard let id else {
      pane = nil
      detail.show(environment.newSession())
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

@MainActor
final class MacDetailController: NSViewController {
  private var current: NSViewController?

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
    show(nil)
  }

  func show(_ controller: NSViewController?) {
    current?.view.removeFromSuperview()
    current?.removeFromParent()
    let next = controller ?? MacPlaceholderController(text: String(localized: "mac.workspace.empty", bundle: .lodyMac))
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.topAnchor.constraint(equalTo: view.topAnchor),
      next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    current = next
  }
}
