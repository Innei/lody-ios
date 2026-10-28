import LodyCore
import UIKit

@MainActor
final class HomeController: UIViewController, UISplitViewControllerDelegate {
  static weak var current: HomeController?
  let source: SessionSource
  private let split = UISplitViewController(style: .doubleColumn)
  private let primary = UINavigationController()
  private let secondary = UINavigationController()
  private let inspector = UINavigationController()
  private let inbox: InboxController
  private var session: SessionController?
  private var scope = ""
  private var observers: [NSObjectProtocol] = []
  private var panelOpen = false
  private var layoutKey = ""
  private let parking = UIViewController()
  private lazy var foldHost = LodyFoldHost.make { [weak self] in self?.view.setNeedsLayout() }
  private var folded = false
  private var hingeOpen = false
  private var foldPanes: [UIViewController] = []
  private var wide: Bool { traitCollection.horizontalSizeClass == .regular && view.bounds.width >= view.bounds.height }

  init(source: SessionSource = .live) {
    self.source = source; inbox = InboxController(source: source)
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  override func viewDidLoad() {
    super.viewDidLoad()
    Self.current = self
    view.accessibilityIdentifier = "home"
    view.backgroundColor = .systemBackground
    split.delegate = self
    split.primaryBackgroundStyle = .none
    split.preferredDisplayMode = .oneBesideSecondary
    split.showsSecondaryOnlyButton = true
    primary.setViewControllers([page(inbox, title: "")], animated: false)
    secondary.setViewControllers([placeholder()], animated: false)
    primary.view.accessibilityIdentifier = "ipad-panel"
    secondary.view.accessibilityIdentifier = "ipad-detail"
    inspector.view.accessibilityIdentifier = "ipad-inspector"
    for (controller, column) in zip([primary, secondary, inspector], [UISplitViewController.Column.primary, .secondary, .inspector]) {
      LodyShell.shared.configureNavigation(controller)
      split.setViewController(controller, for: column)
    }
    adopt(split)
    addChild(parking); parking.view.isHidden = true; view.addSubview(parking.view); parking.didMove(toParent: self)
    LodyFoldHost.observeHinge(on: view) { [weak self] open in self?.hingeOpen = open; self?.layoutColumns() }
    observers = source.changes.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.scopeChanged() }
      }
    }
    scopeChanged()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    primary.traitOverrides.horizontalSizeClass = traitCollection.horizontalSizeClass
    (folded ? foldHost?.controller : split)?.view.frame = view.bounds
    view.accessibilityIdentifier = traitCollection.horizontalSizeClass == .regular ? "ipad-home" : "home"
    layoutColumns()
  }
  private func scopeChanged() {
    let next = source.state.key
    guard next != scope else {
      if let session, !source.state.loading, source.state.catalog.session(session.sessionId) == nil { clearSession() }
      return
    }
    scope = next
    reset()
  }
  func reset() {
    primary.popToRootViewController(animated: false)
    clearSession()
  }
  private func clearSession() {
    session = nil; panelOpen = false
    secondary.setViewControllers([placeholder()], animated: false)
    inspector.setViewControllers([], animated: false)
    inbox.list.selectedSessionId = ""
    primary.viewControllers.flatMap(\.children).compactMap { $0 as? ProjectController }.forEach { $0.list.selectedSessionId = "" }
    layoutColumns()
    if split.isCollapsed { split.show(.primary) }
  }
  func openSession(_ id: String, query: String = "", choice: ModelChoice? = nil) {
    guard source.state.catalog.session(id) != nil else { return }
    if session?.sessionId != id {
      panelOpen = false
      inspector.setViewControllers([], animated: false)
      let next = SessionController(sessionId: id, findQuery: query, choice: choice, source: source)
      session = next
      secondary.setViewControllers([page(next, title: "")], animated: false)
    } else if !query.isEmpty { session?.find(query: query, keyboard: false) }
    inbox.list.selectedSessionId = id
    primary.viewControllers.flatMap(\.children).compactMap { $0 as? ProjectController }.forEach { $0.list.selectedSessionId = id }
    layoutColumns()
    if !folded { split.show(.secondary) }
  }
  func contains(_ controller: UIViewController) -> Bool {
    var ancestor: UIViewController? = controller
    while let current = ancestor {
      if current === self { return true }
      ancestor = current.parent
    }
    return false
  }
  func showPanel(_ content: UIViewController, title: String, from: UIViewController) -> Bool {
    guard wide, contains(from), session != nil else { return false }
    let next = page(content, title: title)
    if from.navigationController === inspector {
      inspector.pushViewController(next, animated: true)
    } else {
      let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), primaryAction: UIAction { [weak self] _ in self?.closePanel() })
      close.accessibilityLabel = String(localized: "accessibility.closePanel", bundle: .lody)
      next.navigationItem.leftBarButtonItem = close
      inspector.setViewControllers([next], animated: false)
    }
    panelOpen = true
    layoutColumns()
    return true
  }
  func closePanel(from controller: UIViewController) -> Bool {
    guard controller.navigationController === inspector else { return false }
    if inspector.viewControllers.count > 1 { inspector.popViewController(animated: true) }
    else { closePanel() }
    return true
  }
  private func closePanel() { panelOpen = false; inspector.setViewControllers([], animated: false); layoutColumns() }
  func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposed: UISplitViewController.Column) -> UISplitViewController.Column {
    if panelOpen { return .inspector }
    return session == nil ? .primary : .secondary
  }
  private func placeholder() -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    controller.view.accessibilityIdentifier = "ipad-detail-placeholder"
    var configuration = UIContentUnavailableConfiguration.empty()
    configuration.image = UIImage(systemName: "bubble.left.and.bubble.right")
    configuration.text = String(localized: "ipad.detail.title", bundle: .lody)
    configuration.secondaryText = String(localized: "ipad.detail.message", bundle: .lody)
    controller.contentUnavailableConfiguration = configuration
    return controller
  }
  private func page(_ content: UIViewController, title: String) -> LodyPageController {
    LodyPageController(spec: .init(title: title, style: "push", animation: "slide", dismissible: true,
      headerShown: true, headerVariant: "transparent"), inSheet: false, content: content)
  }
  private func layoutColumns() {
    guard isViewLoaded else { return }
    let key = "\(wide):\(hingeOpen):\(panelOpen):\(split.isCollapsed)"
    guard key != layoutKey else { return }
    layoutKey = key
    setFolded(wide && hingeOpen && foldHost != nil)
    if folded { placeFoldPanes(); return }
    split.preferredSplitBehavior = wide ? .tile : .overlay
    if panelOpen {
      split.show(.inspector)
      if wide { split.hide(.primary) }
    }
    else {
      split.hide(.inspector)
      if wide { split.show(.primary) }
      else if !split.isCollapsed { split.hide(.primary) }
    }
  }
  private func setFolded(_ value: Bool) {
    guard value != folded, let foldHost else { return }
    release(folded ? foldHost.controller : split)
    if value {
      for column in [UISplitViewController.Column.primary, .secondary, .inspector] { split.setViewController(nil, for: column) }
    } else {
      foldHost.show(leading: nil, trailing: nil); foldPanes = []
      for column in [primary, secondary, inspector] where column.parent === parking { release(column) }
      for (controller, column) in zip([primary, secondary, inspector], [UISplitViewController.Column.primary, .secondary, .inspector]) {
        split.setViewController(controller, for: column)
      }
    }
    folded = value
    adopt(value ? foldHost.controller : split)
  }
  private func placeFoldPanes() {
    guard let foldHost else { return }
    let panes: [UIViewController] = panelOpen ? [secondary, inspector] : [primary, secondary]
    guard panes != foldPanes else { return }
    foldHost.show(leading: nil, trailing: nil)
    for column in [primary, secondary, inspector] where !panes.contains(column) {
      release(column); parking.addChild(column); parking.view.addSubview(column.view); column.didMove(toParent: parking)
    }
    for pane in panes where pane.parent === parking { release(pane) }
    foldHost.show(leading: panes[0], trailing: panes[1]); foldPanes = panes
  }
  private func adopt(_ controller: UIViewController) {
    addChild(controller); view.insertSubview(controller.view, at: 0); controller.view.frame = view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; controller.didMove(toParent: self)
  }
  private func release(_ controller: UIViewController) {
    guard controller.parent != nil else { return }
    controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent()
  }
}
