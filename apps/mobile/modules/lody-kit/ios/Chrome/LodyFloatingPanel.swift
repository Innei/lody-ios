import ExpoModulesCore
import UIKit
import React

/// UIKit owns the existing RN navigation controllers directly, without a second
/// navigation bar. The RN stack views only project UIKit's column geometry.
final class LodySplitView: ExpoView {
  let onColumnLayout = EventDispatcher()
  private let split = LodySplitController(style: .doubleColumn)
  private var stacks: [UIView] = []
  private var columns: [UINavigationController] = []
  private var lastFrames: [CGRect] = []
  private var detailRequest = 0
  private var needsDetail = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    split.primaryBackgroundStyle = .none
    split.preferredDisplayMode = .oneBesideSecondary
    split.showsSecondaryOnlyButton = true
    split.onLayout = { [weak self] in self?.projectColumns() }
  }

  override func mountChildComponentView(_ child: UIView, index: Int) {
    stacks.insert(child, at: index)
    if stacks.count == 2 {
      columns = stacks.compactMap { $0.reactViewController() as? UINavigationController }
      precondition(columns.count == 2, "LodySplitView requires two native ScreenStacks")
      // Establish ownership before the RN stack enters the window, so it does
      // not attach its navigation controller to the outer Router stack.
      split.setViewController(columns[0], for: .primary)
      split.setViewController(columns[1], for: .secondary)
      columns[0].view.accessibilityIdentifier = "ipad-panel"
      columns[1].view.accessibilityIdentifier = "ipad-detail"
      for stack in stacks {
        // Keep the React-owned stack visible to its controller lifecycle and
        // accessibility traversal; its content now lives in UIKit's columns.
        stack.isUserInteractionEnabled = false
        addSubview(stack)
      }
      attach()
    }
  }

  override func unmountChildComponentView(_ child: UIView, index: Int) {
    child.removeFromSuperview()
    stacks.removeAll { $0 === child }
    split.setViewController(nil, for: index == 0 ? .primary : .secondary)
    columns = []
    lastFrames = []
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attach()
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if superview == nil {
      split.willMove(toParent: nil)
      split.view.removeFromSuperview()
      split.removeFromParent()
    }
  }

  private func attach() {
    guard window != nil, columns.count == 2 else { return }
    if split.parent == nil, let owner = reactViewController() {
      owner.addChild(split)
      insertSubview(split.view, at: 0)
      split.view.frame = bounds
      split.didMove(toParent: owner)
    }
    revealDetailIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    split.view.frame = bounds
  }

  func setHasDetail(_ value: Bool) {
    split.hasDetail = value
  }

  func setDetailRequest(_ value: Int) {
    guard value != detailRequest else { return }
    detailRequest = value
    needsDetail = true
    DispatchQueue.main.async { [weak self] in self?.revealDetailIfNeeded() }
  }

  private func revealDetailIfNeeded() {
    guard needsDetail, split.view.window != nil, columns.count == 2 else { return }
    needsDetail = false
    if split.isCollapsed {
      split.show(.secondary)
    } else if split.splitBehavior != .tile {
      split.hide(.primary)
    }
  }

  private func projectColumns() {
    guard columns.count == 2 else { return }
    let frames = columns.map { $0.view.convert($0.view.bounds, to: self) }
    guard frames != lastFrames, frames.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { return }
    lastFrames = frames
    func values(_ rect: CGRect) -> [String: CGFloat] {
      ["left": rect.minX, "top": rect.minY, "width": rect.width, "height": rect.height]
    }
    onColumnLayout(["primary": values(frames[0]), "secondary": values(frames[1])])
  }
}

private final class LodySplitController: UISplitViewController, UISplitViewControllerDelegate {
  var onLayout: (() -> Void)?
  var hasDetail = false

  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }

  func splitViewController(
    _ svc: UISplitViewController,
    topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
  ) -> UISplitViewController.Column {
    hasDetail ? .secondary : .primary
  }
}


struct EmbeddedSheetDetent {
  enum Identifier: String {
    case medium
    case large
  }

  let identifier: Identifier
  let resolve: (CGFloat) -> CGFloat

  static func medium(fraction: CGFloat = 0.62) -> Self {
    Self(identifier: .medium) { $0 * fraction }
  }

  static func large() -> Self {
    Self(identifier: .large) { $0 }
  }
}

final class EmbeddedSheetViewController: UIViewController, UIGestureRecognizerDelegate {
  var detents = [EmbeddedSheetDetent.medium(), .large()]
  var selectedDetentIdentifier: EmbeddedSheetDetent.Identifier = .medium {
    didSet {
      guard selectedDetentIdentifier != oldValue, !suppressSelectionUpdate else { return }
      updateSelectedDetent(animated: animateSelectionChanges)
    }
  }
  var prefersGrabberVisible = true {
    didSet { grabberTarget.isHidden = !prefersGrabberVisible }
  }
  var prefersScrollingExpandsWhenScrolledToEdge = true
  var onDismiss: (() -> Void)?

  let contentView = UIView()
  private let dimmingView = UIControl()
  private let sheetView = UIView()
  private let grabberTarget = EmbeddedSheetGrabber()
  private let grabber = UIView()
  private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
  private weak var activeScrollView: UIScrollView?
  private var currentHeight: CGFloat = 0
  private var interactionStartHeight: CGFloat = 0
  private var animator: UIViewPropertyAnimator?
  private var animateSelectionChanges = false
  private var suppressSelectionUpdate = false
  private var presented = false
  private var dismissing = false

  override func loadView() {
    view = UIView()
    view.backgroundColor = .clear

    dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
    dimmingView.alpha = 0
    dimmingView.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)
    view.addSubview(dimmingView)

    sheetView.backgroundColor = .secondarySystemGroupedBackground
    sheetView.layer.cornerCurve = .continuous
    sheetView.layer.cornerRadius = 24
    sheetView.accessibilityIdentifier = "ipad-sheet-surface"
    sheetView.layer.shadowColor = UIColor.black.cgColor
    sheetView.layer.shadowOffset = CGSize(width: 0, height: -4)
    sheetView.layer.shadowOpacity = 0.16
    sheetView.layer.shadowRadius = 16
    sheetView.clipsToBounds = true
    view.addSubview(sheetView)

    contentView.backgroundColor = .clear
    sheetView.addSubview(contentView)

    grabber.backgroundColor = .tertiaryLabel
    grabber.layer.cornerRadius = 2.5
    grabberTarget.addSubview(grabber)
    grabberTarget.controller = self
    grabberTarget.isAccessibilityElement = true
    grabberTarget.accessibilityTraits = .adjustable
    sheetView.addSubview(grabberTarget)

    pan.delegate = self
    pan.cancelsTouchesInView = false
    sheetView.addGestureRecognizer(pan)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    dimmingView.frame = view.bounds
    guard !dismissing else {
      applySheetFrame()
      return
    }
    if pan.state != .began, pan.state != .changed, animator?.isRunning != true {
      currentHeight = resolvedHeight(selectedDetentIdentifier)
    }
    applySheetFrame()
  }

  func setContent(_ child: UIView) {
    // Adopt SheetStack's native controller before its React proxy enters the
    // window. UIKit, not the sidebar's Yoga frame, owns the sheet content size.
    guard let navigation = child.reactViewController() as? UINavigationController else { return }
    addChild(navigation)
    contentView.addSubview(navigation.view)
    navigation.view.frame = contentView.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    navigation.didMove(toParent: self)
  }

  func removeContent(_ child: UIView) {
    guard let navigation = child.reactViewController(), navigation.parent === self else { return }
    navigation.willMove(toParent: nil)
    navigation.view.removeFromSuperview()
    navigation.removeFromParent()
  }

  func setGrabberAccessibility(label: String, medium: String, large: String) {
    grabberTarget.accessibilityLabel = label
    grabberTarget.mediumValue = medium
    grabberTarget.largeValue = large
    updateGrabberAccessibilityValue()
  }

  func setGrabberAccessibilityIdentifier(_ value: String) {
    grabberTarget.accessibilityIdentifier = value
  }

  func presentSheet() {
    guard !presented else { return }
    presented = true
    view.layoutIfNeeded()
    currentHeight = 0
    applySheetFrame()
    animate(to: resolvedHeight(selectedDetentIdentifier), velocityY: 0)
  }

  func animateChanges(_ changes: () -> Void) {
    animateSelectionChanges = true
    changes()
    animateSelectionChanges = false
  }

  @objc func dismissSheet() {
    guard !dismissing else { return }
    dismissing = true
    view.isUserInteractionEnabled = false
    view.endEditing(true)
    animate(to: 0, velocityY: 0) { [weak self] in self?.dismiss(animated: false) }
  }

  func accessibilityExpand() {
    guard !dismissing else { return }
    animateChanges { selectedDetentIdentifier = .large }
  }

  func accessibilityCollapse() {
    guard !dismissing else { return }
    animateChanges { selectedDetentIdentifier = .medium }
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === pan, !dismissing else { return false }
    let velocity = pan.velocity(in: sheetView)
    guard abs(velocity.y) > abs(velocity.x) else { return false }
    if grabberTarget.bounds.contains(pan.location(in: grabberTarget)) {
      activeScrollView = nil
      return true
    }
    let scrollView = scrollView(containing: sheetView.hitTest(pan.location(in: sheetView), with: nil))
    activeScrollView = scrollView
    guard let scrollView else { return true }
    let atTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
    if velocity.y > 0 { return atTop }
    return prefersScrollingExpandsWhenScrolledToEdge
      && selectedDetentIdentifier == .medium
      && atTop
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    gestureRecognizer === pan && otherGestureRecognizer.view is UIScrollView
  }

  @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      if let frame = sheetView.layer.presentation()?.frame { currentHeight = frame.height }
      animator?.stopAnimation(true)
      animator = nil
      applySheetFrame()
      interactionStartHeight = currentHeight
    case .changed:
      pinActiveScrollViewToTop()
      let proposed = interactionStartHeight - gesture.translation(in: view).y
      currentHeight = rubberBanded(proposed)
      applySheetFrame()
      dimmingView.alpha = min(1, currentHeight / max(resolvedHeight(.medium), 1))
    case .ended, .cancelled:
      let velocityY = gesture.velocity(in: view).y
      let projected = currentHeight - velocityY * 0.2
      let target = nearestTarget(to: projected, velocityY: velocityY)
      if target == nil {
        dismissing = true
        view.isUserInteractionEnabled = false
        view.endEditing(true)
        animate(to: 0, velocityY: velocityY) { [weak self] in self?.dismiss(animated: false) }
      } else if let target {
        suppressSelectionUpdate = true
        selectedDetentIdentifier = target
        suppressSelectionUpdate = false
        updateGrabberAccessibilityValue()
        animate(to: resolvedHeight(target), velocityY: velocityY)
      }
      activeScrollView = nil
    default:
      break
    }
  }

  private func updateSelectedDetent(animated: Bool) {
    guard isViewLoaded, presented, !dismissing else { return }
    updateGrabberAccessibilityValue()
    let height = resolvedHeight(selectedDetentIdentifier)
    if animated { animate(to: height, velocityY: 0) }
    else {
      currentHeight = height
      applySheetFrame()
    }
  }

  private func animate(to height: CGFloat, velocityY: CGFloat, completion: (() -> Void)? = nil) {
    if let frame = sheetView.layer.presentation()?.frame { currentHeight = frame.height }
    animator?.stopAnimation(true)
    animator = nil
    applySheetFrame()
    let distance = max(abs(height - currentHeight), 1)
    let normalizedVelocity = min(max(velocityY / distance, -20), 20)
    let timing = UISpringTimingParameters(
      dampingRatio: 0.86,
      initialVelocity: CGVector(dx: 0, dy: normalizedVelocity)
    )
    let animator = UIViewPropertyAnimator(duration: 0.42, timingParameters: timing)
    currentHeight = height
    animator.addAnimations {
      self.applySheetFrame()
      self.dimmingView.alpha = height == 0 ? 0 : 1
    }
    animator.addCompletion { [weak self] position in
      guard let self else { return }
      self.animator = nil
      if position == .end { completion?() }
    }
    self.animator = animator
    animator.startAnimation()
  }

  private func applySheetFrame() {
    let height = max(0, currentHeight)
    let medium = resolvedHeight(.medium)
    let expansion = min(1, max(0, (height - medium) / max(view.bounds.height - medium, 1)))
    let inset = 10 * (1 - expansion)
    let radius = 24 * (1 - expansion)
    sheetView.frame = CGRect(x: inset, y: view.bounds.height - height - inset, width: view.bounds.width - inset * 2, height: height)
    sheetView.layer.cornerRadius = radius
    contentView.frame = CGRect(x: 0, y: 14, width: sheetView.bounds.width, height: max(0, height - 14))
    grabberTarget.frame = CGRect(x: 0, y: 0, width: sheetView.bounds.width, height: 28)
    grabber.frame = CGRect(x: (grabberTarget.bounds.width - 36) / 2, y: 6, width: 36, height: 5)
    sheetView.bringSubviewToFront(grabberTarget)
    sheetView.layer.shadowPath = UIBezierPath(
      roundedRect: sheetView.bounds,
      cornerRadius: radius
    ).cgPath
  }

  private func resolvedHeight(_ identifier: EmbeddedSheetDetent.Identifier) -> CGFloat {
    let height = detents.first(where: { $0.identifier == identifier })?.resolve(view.bounds.height) ?? view.bounds.height
    return identifier == .medium ? max(0, height - 10) : height
  }

  private func nearestTarget(
    to projectedHeight: CGFloat,
    velocityY: CGFloat
  ) -> EmbeddedSheetDetent.Identifier? {
    let medium = resolvedHeight(.medium)
    if selectedDetentIdentifier == .medium,
      currentHeight < medium - 90 || velocityY > 900
    {
      return nil
    }
    let candidates: [(EmbeddedSheetDetent.Identifier?, CGFloat)] = [
      (nil, 0),
      (.medium, medium),
      (.large, resolvedHeight(.large)),
    ]
    return candidates.min(by: { abs($0.1 - projectedHeight) < abs($1.1 - projectedHeight) })?.0
  }

  private func rubberBanded(_ proposed: CGFloat) -> CGFloat {
    let maximum = resolvedHeight(.large)
    if proposed < 0 { return -rubberBand(-proposed, dimension: maximum) }
    if proposed > maximum { return maximum + rubberBand(proposed - maximum, dimension: maximum) }
    return proposed
  }

  private func rubberBand(_ distance: CGFloat, dimension: CGFloat) -> CGFloat {
    (1 - 1 / (distance * 0.55 / max(dimension, 1) + 1)) * dimension
  }

  private func scrollView(containing view: UIView?) -> UIScrollView? {
    var current = view
    while let item = current, item !== sheetView {
      if let scrollView = item as? UIScrollView { return scrollView }
      current = item.superview
    }
    return nil
  }

  private func pinActiveScrollViewToTop() {
    guard let scrollView = activeScrollView else { return }
    scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
  }

  private func updateGrabberAccessibilityValue() {
    grabberTarget.accessibilityValue = selectedDetentIdentifier == .large
      ? grabberTarget.largeValue
      : grabberTarget.mediumValue
  }
}

private final class EmbeddedSheetGrabber: UIControl {
  weak var controller: EmbeddedSheetViewController?
  var mediumValue = ""
  var largeValue = ""

  override func accessibilityIncrement() { controller?.accessibilityExpand() }
  override func accessibilityDecrement() { controller?.accessibilityCollapse() }
}

private final class SidebarSheetPresentation: UIPresentationController {
  weak var sidebar: UIView?
  private var hiddenBackground: [(UIView, Bool)] = []

  override var shouldPresentInFullscreen: Bool { false }
  override var frameOfPresentedViewInContainerView: CGRect {
    sidebar.map { $0.convert($0.bounds, to: containerView) } ?? .zero
  }

  override func presentationTransitionWillBegin() {
    hiddenBackground = sidebar?.subviews.filter { $0 !== containerView }.map { ($0, $0.accessibilityElementsHidden) } ?? []
    hiddenBackground.forEach { $0.0.accessibilityElementsHidden = true }
    presentedView?.accessibilityViewIsModal = true
    containerView?.accessibilityViewIsModal = true
  }

  override func containerViewWillLayoutSubviews() {
    super.containerViewWillLayoutSubviews()
    presentedView?.frame = frameOfPresentedViewInContainerView
  }

  override func dismissalTransitionDidEnd(_ completed: Bool) {
    guard completed else { return }
    finishPresentation()
  }

  override func presentationTransitionDidEnd(_ completed: Bool) {
    if !completed { finishPresentation() }
  }

  private func finishPresentation() {
    hiddenBackground.forEach { $0.0.accessibilityElementsHidden = $0.1 }
    hiddenBackground.removeAll()
    (presentedViewController as? EmbeddedSheetViewController)?.onDismiss?()
  }
}

final class LodyEmbeddedSheet: ExpoView, UIViewControllerTransitioningDelegate {
  let onDismiss = EventDispatcher()
  private let controller = EmbeddedSheetViewController()
  private var lastDismissRequest = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    controller.loadViewIfNeeded()
    controller.modalPresentationStyle = .custom
    controller.transitioningDelegate = self
    controller.onDismiss = { [weak self] in self?.onDismiss([:]) }
  }

  override func mountChildComponentView(_ childComponentView: UIView, index: Int) {
    controller.setContent(childComponentView)
    addSubview(childComponentView)
  }

  override func unmountChildComponentView(_ childComponentView: UIView, index: Int) {
    controller.removeContent(childComponentView)
    childComponentView.removeFromSuperview()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      controller.dismiss(animated: false)
      return
    }
    DispatchQueue.main.async { [weak self] in self?.presentSheet() }
  }

  private func presentSheet() {
    guard window != nil, controller.presentingViewController == nil else { return }
    guard let owner = owningController(), let navigation = owner.navigationController,
      navigation.presentedViewController == nil else {
      onDismiss([:])
      return
    }
    owner.definesPresentationContext = false
    navigation.definesPresentationContext = true
    navigation.view.endEditing(true)
    // The inner navigation bar must enter the window at its actual sheet size.
    controller.view.frame = navigation.view.bounds
    controller.view.layoutIfNeeded()
    navigation.present(controller, animated: false) { [weak self] in self?.controller.presentSheet() }
  }

  func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
    let presentation = SidebarSheetPresentation(presentedViewController: presented, presenting: presenting)
    presentation.sidebar = owningController()?.navigationController?.view
    return presentation
  }

  func setMediumFraction(_ value: Double) {
    controller.detents = [.medium(fraction: min(max(CGFloat(value), 0.25), 0.95)), .large()]
  }

  func setDismissRequest(_ value: Int) {
    guard value > lastDismissRequest else { return }
    lastDismissRequest = value
    controller.dismissSheet()
  }

  func setGrabberAccessibilityIdentifier(_ value: String) {
    controller.setGrabberAccessibilityIdentifier(value)
  }

  func setGrabberAccessibility(label: String, medium: String, large: String) {
    controller.setGrabberAccessibility(label: label, medium: medium, large: large)
  }

  private func owningController() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }
}
