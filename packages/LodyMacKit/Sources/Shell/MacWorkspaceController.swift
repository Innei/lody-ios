import AppKit
import LodyData

@MainActor
final class MacWorkspaceController: NSSplitViewController, MacStreamingTab {
  let environment: MacEnvironment
  let sidebar: SidebarViewController
  private let detail = MacDetailController()
  private var pane: MacSessionPane?
  private var streaming = false
  private(set) var sessionId: String?
  var onTitle: ((_ title: String, _ subtitle: String) -> Void)?
  var onNewSession: (() -> Void)?

  init(environment: MacEnvironment) {
    self.environment = environment
    sidebar = SidebarViewController(source: environment.sessions)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

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
    sidebar.onNewSession = { [weak self] in self?.onNewSession?() }
  }

  func open(_ id: String?) {
    guard id != sessionId || pane == nil else { return }
    pane?.setStreaming(false)
    sessionId = id
    sidebar.select(sessionId: id)
    guard let id else {
      pane = nil
      detail.show(nil)
      onTitle?("Lody", "")
      return
    }
    let next = environment.pane(id)
    pane = next
    detail.show(next)
    next.setStreaming(streaming)
    let state = environment.sessions.read()
    let session = state.catalog.session(id)
    let project = state.catalog.projects.first { $0.id == session?.projectId }?.name ?? ""
    onTitle?(session?.title ?? "Lody", project)
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
