import ExpoModulesCore
import UIKit
import React

/// UIKit owns the existing RN navigation controllers directly, without a second
/// navigation bar. The RN stack views only project UIKit's column geometry.
final class LodySplitView: ExpoView {
  let onColumnLayout = EventDispatcher()
  private static let placements: [UISplitViewController.Column] = [.primary, .secondary, .inspector]
  private let split = LodySplitController(style: .doubleColumn)
  private let compactPlaceholder = UIViewController()
  // Holds the column the fold arrangement does not show. A navigation
  // controller without a parent is re-adopted by its RN stack into the outer
  // Router controller, which would draw it over the arrangement.
  private let parking = UIViewController()
  private lazy var foldHost = LodyFoldHost.make { [weak self] in self?.projectColumns() }
  private var folded = false
  private var foldPanes: [UIViewController] = []
  private var stacks: [UIView] = []
  private var columns: [UINavigationController] = []
  private var lastFrames: [String: CGRect] = [:]
  private var detailRequest = 0
  private var needsDetail = false
  private var layoutMode = "wide"
  private var panelOpen = false
  private var hingeOpen = false

  private var host: UIViewController {
    if folded, let foldHost { return foldHost.controller }
    return split
  }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    split.primaryBackgroundStyle = .none
    split.preferredDisplayMode = .oneBesideSecondary
    split.showsSecondaryOnlyButton = true
    split.onLayout = { [weak self] in self?.projectColumns() }
    compactPlaceholder.view.backgroundColor = .lodyBackground
    parking.view.isHidden = true
    LodyFoldHost.observeHinge(on: self) { [weak self] open in
      guard let self, open != hingeOpen else { return }
      hingeOpen = open
      applyLayout()
    }
  }

  override func mountChildComponentView(_ child: UIView, index: Int) {
    stacks.insert(child, at: index)
    guard stacks.count == Self.placements.count else { return }
    columns = stacks.compactMap { $0.reactViewController() as? UINavigationController }
    precondition(columns.count == Self.placements.count, "LodySplitView requires three native ScreenStacks")
    // Establish ownership before the RN stack enters the window, so it does
    // not attach its navigation controller to the outer Router stack.
    for (column, placement) in zip(columns, Self.placements) {
      split.setViewController(column, for: placement)
    }
    // Collapsing would otherwise merge the RN-owned stacks into one navigation
    // controller before JS replaces this split with the compact home.
    split.setViewController(compactPlaceholder, for: .compact)
    columns[0].view.accessibilityIdentifier = "ipad-panel"
    columns[1].view.accessibilityIdentifier = "ipad-detail"
    columns[2].view.accessibilityIdentifier = "ipad-inspector"
    for stack in stacks {
      // Keep the React-owned stack visible to its controller lifecycle and
      // accessibility traversal; its content now lives in UIKit's columns.
      stack.isUserInteractionEnabled = false
      addSubview(stack)
    }
    applyLayout()
    attach()
  }

  override func unmountChildComponentView(_ child: UIView, index: Int) {
    child.removeFromSuperview()
    stacks.removeAll { $0 === child }
    setFolded(false)
    if Self.placements.indices.contains(index) {
      split.setViewController(nil, for: Self.placements[index])
    }
    columns = []
    lastFrames = [:]
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attach()
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if superview == nil {
      for controller in [host, parking] {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
      }
    }
  }

  private func attach() {
    guard window != nil, columns.count == Self.placements.count, let owner = reactViewController() else { return }
    if parking.parent == nil {
      owner.addChild(parking)
      addSubview(parking.view)
      parking.didMove(toParent: owner)
    }
    if host.parent == nil { adopt(host, owner: owner) }
    applyLayout()
    revealDetailIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    host.view.frame = bounds
  }

  func setLayoutMode(_ value: String) {
    guard value != layoutMode else { return }
    layoutMode = value
    applyLayout()
  }

  func setPanelOpen(_ value: Bool) {
    guard value != panelOpen else { return }
    panelOpen = value
    applyLayout()
  }

  func setDetailRequest(_ value: Int) {
    guard value != detailRequest else { return }
    detailRequest = value
    needsDetail = true
    DispatchQueue.main.async { [weak self] in self?.revealDetailIfNeeded() }
  }

  private var wantsFold: Bool {
    layoutMode == "wide" && hingeOpen && columns.count == Self.placements.count && foldHost != nil
  }

  private func applyLayout() {
    let wide = layoutMode == "wide"
    split.preferredSplitBehavior = wide ? .tile : .overlay
    guard columns.count == Self.placements.count else {
      split.preferredDisplayMode = wide ? .oneBesideSecondary : .secondaryOnly
      return
    }
    setFolded(wantsFold)
    if folded {
      placeFoldPanes()
    } else if wide && panelOpen {
      split.show(.inspector)
      split.hide(.primary)
    } else {
      split.hide(.inspector)
      if wide { split.show(.primary) } else { split.hide(.primary) }
    }
  }

  private func setFolded(_ value: Bool) {
    guard value != folded, let foldHost else { return }
    let owner = host.parent
    release(host)
    if value {
      for placement in Self.placements { split.setViewController(nil, for: placement) }
    } else {
      foldHost.show(leading: nil, trailing: nil)
      foldPanes = []
      for column in columns where column.parent === parking { release(column) }
      for (column, placement) in zip(columns, Self.placements) {
        split.setViewController(column, for: placement)
      }
    }
    folded = value
    if let owner { adopt(host, owner: owner) }
  }

  // The arrangement has two slots, so an open panel takes the trailing half
  // and the chat moves to the leading half while the list waits in parking.
  private func placeFoldPanes() {
    guard let foldHost else { return }
    let panes: [UIViewController] = panelOpen ? [columns[1], columns[2]] : [columns[0], columns[1]]
    guard panes != foldPanes else { return }
    foldHost.show(leading: nil, trailing: nil)
    for column in columns where !panes.contains(column) { park(column) }
    for pane in panes where pane.parent === parking { release(pane) }
    foldHost.show(leading: panes[0], trailing: panes[1])
    foldPanes = panes
  }

  private func park(_ column: UIViewController) {
    guard column.parent !== parking else { return }
    release(column)
    parking.addChild(column)
    parking.view.addSubview(column.view)
    column.didMove(toParent: parking)
  }

  private func adopt(_ controller: UIViewController, owner: UIViewController) {
    owner.addChild(controller)
    insertSubview(controller.view, at: 0)
    controller.view.frame = bounds
    controller.didMove(toParent: owner)
  }

  private func release(_ controller: UIViewController) {
    guard controller.parent != nil else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  private func revealDetailIfNeeded() {
    guard needsDetail, split.view.window != nil, columns.count == Self.placements.count else { return }
    needsDetail = false
    if split.isCollapsed {
      split.show(.secondary)
    } else if split.splitBehavior != .tile {
      split.hide(.primary)
    }
  }

  private func projectColumns() {
    guard columns.count == Self.placements.count else { return }
    var frames = lastFrames
    for (name, column) in zip(["primary", "secondary", "inspector"], columns) where column.parent !== parking {
      let frame = column.view.convert(column.view.bounds, to: self)
      if frame.width > 0, frame.height > 0 { frames[name] = frame }
    }
    guard frames != lastFrames else { return }
    lastFrames = frames
    onColumnLayout(frames.mapValues { rect in
      ["left": rect.minX, "top": rect.minY, "width": rect.width, "height": rect.height]
    })
  }
}

private final class LodySplitController: UISplitViewController {
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }

  // A shown inspector becomes a modal sheet when the split collapses, which
  // would present an RN-owned navigation controller.
  override func willTransition(
    to newCollection: UITraitCollection,
    with coordinator: any UIViewControllerTransitionCoordinator
  ) {
    if newCollection.horizontalSizeClass == .compact { hide(.inspector) }
    super.willTransition(to: newCollection, with: coordinator)
  }
}
