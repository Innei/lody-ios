import ExpoModulesCore
import UIKit

/// Morphs the next sheet presentation out of a bar button, Telegram
/// attachment-menu style. Armed right before JS presents a sheet without
/// animation; the patched native stack posts `RNSScreenWillAppear` from inside
/// the presentation, before UIKit flushes the sheet's first frame, so the
/// sheet is hidden before it ever renders. Only presentation-layer animations
/// run afterwards so the sheet controller's own layout never conflicts.
/// `dismiss` plays the same morph backwards and leaves the sheet hidden for an
/// unanimated removal.
@MainActor
enum LodyMorphReveal {
  private static var token: NSObjectProtocol?
  private static var timeout: DispatchWorkItem?
  private static weak var hidden: UIView?
  private static var dismissal: MorphDismissal?

  static func prepare(sourceLabel: String) {
    cancel()
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return }
    let source = findSource(label: sourceLabel, from: root)
    // UIKit installs a backdrop in both the sheet container and the presenting
    // window's wrapper. Preserve any dimming owned by an earlier presentation.
    let existingDimming = Set(dimmingViews(in: root.view.window).filter {
      !$0.isHidden && $0.alpha > 0
    }.map(ObjectIdentifier.init))
    token = NotificationCenter.default.addObserver(
      forName: Notification.Name("RNSScreenWillAppear"), object: nil, queue: nil
    ) { notification in
      nonisolated(unsafe) let object = notification.object
      MainActor.assumeIsolated {
        guard let presented = object as? UIViewController, presented.presentingViewController != nil,
          presented.sheetPresentationController != nil,
          let sheet = presented.presentationController?.presentedView
        else { return }
        // Fabric re-applies the screen's opacity on later commits, so the
        // content hide lives in the presentation layer.
        presented.view.layer.add(hold, forKey: "morphHold")
        hidden = presented.view
        sheet.mask = UIView()
        let dimming = Array(Set(
          dimmingViews(in: root.view.window, excluding: sheet)
            + dimmingViews(in: presented.presentationController?.containerView, excluding: sheet)
        )).filter {
          !existingDimming.contains(ObjectIdentifier($0))
        }
        dimming.forEach { $0.alpha = 0 }
        cancel()
        DispatchQueue.main.async { reveal(presented: presented, sheet: sheet, dimming: dimming, source: source) }
      }
    }
    let timeout = DispatchWorkItem {
      hidden?.layer.removeAnimation(forKey: "morphHold")
      cancel()
    }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
  }

  private static func cancel() {
    timeout?.cancel()
    timeout = nil
    hidden = nil
    if let token {
      NotificationCenter.default.removeObserver(token)
      self.token = nil
    }
  }

  static func dismiss(completion: @escaping () -> Void) {
    guard let state = dismissal, let presented = state.presented,
      let sheet = presented.presentationController?.presentedView
    else { return completion() }
    state.completions.append(completion)
    guard !state.closing else { return }
    state.closing = true
    let dimming = state.dimming
    presented.view.isUserInteractionEnabled = false
    morph(presented: presented, sheet: sheet, dimming: dimming, source: state.source, sourceFrame: state.sourceFrame, reverse: true) {
      presented.view.alpha = 0
      dimming.forEach { $0.alpha = 0 }
      presented.presentationController?.delegate = state.original
      state.backdrop.view?.removeGestureRecognizer(state.backdrop)
      dismissal = nil
      state.completions.forEach { $0() }
      state.completions.removeAll()
    }
  }

  private static func reveal(presented: UIViewController, sheet: UIView, dimming: [UIView], source: UIView?) {
    let content = presented.view!
    content.layer.removeAnimation(forKey: "morphHold")
    sheet.mask = nil
    UIView.animate(withDuration: 0.3) {
      dimming.forEach { $0.alpha = 1 }
    }
    guard let source, source.window != nil, source.bounds.width > 0 else {
      content.layer.add(basic("opacity", from: 0, to: 1, duration: 0.2), forKey: "morph")
      return
    }
    if let presentation = presented.presentationController, let container = presentation.containerView {
      // Sending pushes the destination underneath this sheet. Its toolbar no
      // longer owns the source button, so retain the opening geometry.
      let state = MorphDismissal(presented: presented, source: source,
        sourceFrame: source.convert(source.bounds, to: container), dimming: dimming)
      dismissal = state
      presentation.delegate = state
    }
    morph(presented: presented, sheet: sheet, dimming: dimming, source: source, reverse: false) {}
  }

  private static func morph(presented: UIViewController, sheet: UIView, dimming: [UIView], source: UIView, sourceFrame: CGRect? = nil, reverse: Bool, completion: @escaping () -> Void) {
    guard let container = presented.presentationController?.containerView else { return completion() }
    let content = presented.view!
    container.layoutIfNeeded()
    let targetFrame = sheet.convert(sheet.bounds, to: container)
    let sourceFrame = sourceFrame ?? source.convert(source.bounds, to: container)
    let scale = sourceFrame.width / targetFrame.width
    let square = CGRect(x: 0, y: 0, width: sheet.bounds.width, height: sheet.bounds.width)
    let cornerRadius: CGFloat = 38
    let duration = reverse ? 0.3 : 0.4
    let damping: CGFloat = reverse ? 124 : 110

    let iconCarrier = UIView(frame: targetFrame)
    let icon = UIImageView(image: UIImage(systemName: "plus"))
    icon.preferredSymbolConfiguration = .init(pointSize: 17, weight: .semibold)
    icon.tintColor = source.tintColor
    icon.sizeToFit()
    icon.center = CGPoint(x: targetFrame.width / 2, y: targetFrame.height / 2)
    icon.transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
    icon.alpha = reverse ? 1 : 0
    iconCarrier.addSubview(icon)
    container.addSubview(iconCarrier)

    // The sheet material is drawn by UIKit's wrapper, which re-lays out and
    // strips its own animations while the sheet settles but leaves its mask
    // alone: the reveal clip animates on the wrapper's mask (in the wrapper's
    // inset, scaled coordinates) and the motion runs on the screen content.
    let mask = UIView(frame: CGRect(origin: .zero, size: sheet.bounds.size))
    mask.backgroundColor = .black
    mask.layer.cornerCurve = .continuous
    mask.layer.cornerRadius = cornerRadius
    sheet.mask = mask
    let shadowOpacity = sheet.layer.shadowOpacity
    sheet.layer.shadowOpacity = 0

    source.isHidden = true
    let sourceCenter = container.convert(sourceFrame.center, to: sheet)
    let small = NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1))
    let full = NSValue(caTransform3D: CATransform3DIdentity)
    // Backwards, the model state is the open sheet, so the animations keep
    // their final frame until the cleanup below hides the sheet for real.
    func hold<T: CAAnimation>(_ animation: T) -> T {
      if reverse {
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
      }
      return animation
    }
    func spring(_ keyPath: String, _ a: Any, _ b: Any, _ seconds: CFTimeInterval, velocity: CGFloat = 0) -> CASpringAnimation {
      hold(Self.spring(keyPath, from: reverse ? b : a, to: reverse ? a : b, duration: seconds, damping: damping, velocity: velocity))
    }
    func basic(_ keyPath: String, _ a: Any, _ b: Any, _ seconds: CFTimeInterval) -> CABasicAnimation {
      hold(Self.basic(keyPath, from: reverse ? b : a, to: reverse ? a : b, duration: seconds))
    }
    let corners = basic("cornerRadius", targetFrame.width / 2, cornerRadius, 0.2)
    corners.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    iconCarrier.layer.add(spring("position", NSValue(cgPoint: sourceFrame.center), NSValue(cgPoint: targetFrame.center), duration, velocity: 1.1), forKey: "morphPosition")
    iconCarrier.layer.add(spring("transform", small, full, duration), forKey: "morphScale")
    content.layer.add(spring("position", NSValue(cgPoint: sourceCenter), NSValue(cgPoint: content.layer.position), duration, velocity: 1.1), forKey: "morphPosition")
    content.layer.add(spring("transform", small, full, duration), forKey: "morphScale")
    content.layer.add(basic("opacity", 0, 1, 0.2), forKey: "morphOpacity")
    mask.layer.add(spring("position", NSValue(cgPoint: sourceCenter), NSValue(cgPoint: mask.layer.position), duration, velocity: 1.1), forKey: "morphPosition")
    mask.layer.add(spring("transform", small, full, duration), forKey: "morphScale")
    mask.layer.add(spring("bounds", NSValue(cgRect: square), NSValue(cgRect: mask.bounds), duration), forKey: "morphBounds")
    mask.layer.add(corners, forKey: "morphCorners")
    icon.layer.add(basic("opacity", 1, 0, 0.15), forKey: "morphOpacity")
    if reverse {
      UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
        dimming.forEach { $0.alpha = 0 }
      }
    }
    #if DEBUG
    let probe = MorphProbe(content: content, dimming: dimming, reverse: reverse)
    #endif
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
      #if DEBUG
      probe.stop()
      #endif
      completion()
      sheet.mask = reverse ? UIView() : nil
      sheet.layer.shadowOpacity = shadowOpacity
      iconCarrier.removeFromSuperview()
      source.isHidden = false
      if reverse {
        content.layer.removeAllAnimations()
      }
    }
  }

  private static func dimmingViews(in view: UIView?, excluding sheet: UIView? = nil) -> [UIView] {
    guard let view, view !== sheet else { return [] }
    if String(describing: type(of: view)).localizedCaseInsensitiveContains("dimming") { return [view] }
    return view.subviews.flatMap { dimmingViews(in: $0, excluding: sheet) }
  }

  private final class MorphDismissal: NSObject, UIAdaptivePresentationControllerDelegate, UIGestureRecognizerDelegate {
    weak var presented: UIViewController?
    weak var original: UIAdaptivePresentationControllerDelegate?
    let source: UIView
    let sourceFrame: CGRect
    let dimming: [UIView]
    var closing = false
    var completions: [() -> Void] = []
    let backdrop = UITapGestureRecognizer()

    init(presented: UIViewController, source: UIView, sourceFrame: CGRect, dimming: [UIView]) {
      self.presented = presented
      self.original = presented.presentationController?.delegate
      self.source = source
      self.sourceFrame = sourceFrame
      self.dimming = dimming
      super.init()
      backdrop.addTarget(self, action: #selector(tapBackdrop))
      backdrop.delegate = self
      backdrop.cancelsTouchesInView = false
      presented.presentationController?.containerView?.addGestureRecognizer(backdrop)
    }

    @objc private func tapBackdrop() {
      guard let presentation = presented?.presentationController else { return }
      presentationControllerDidAttemptToDismiss(presentation)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard !closing, let presented, presented.presentedViewController == nil,
        let sheet = presented.presentationController?.presentedView else { return false }
      return !sheet.point(inside: touch.location(in: sheet), with: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    override func responds(to selector: Selector!) -> Bool {
      super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? { original }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
      // UIKit also asks speculatively (including accessibility queries).
      // Start the morph only for an actual attempt below.
      false
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
      guard !closing else { return }
      guard original?.presentationControllerShouldDismiss?(presentationController) != false else {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
        return
      }
      LodyMorphReveal.dismiss { [self] in
        presented?.dismiss(animated: false) {
          self.original?.presentationControllerDidDismiss?(presentationController)
        }
      }
    }
  }

  private static func findSource(label: String, from controller: UIViewController) -> UIView? {
    var items = controller.toolbarItems ?? []
    items += controller.navigationItem.leftBarButtonItems ?? []
    items += controller.navigationItem.rightBarButtonItems ?? []
    // UIBarButtonItem has no public view accessor, and the iOS 26 bottom bar
    // is not a UIToolbar, so items are matched on their owning controllers.
    if let item = items.first(where: { $0.accessibilityLabel == label }),
      let view = item.value(forKey: "view") as? UIView, view.window != nil
    {
      return view
    }
    for child in controller.children {
      if let match = findSource(label: label, from: child) { return match }
    }
    return nil
  }

  private static var hold: CABasicAnimation {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 0
    animation.toValue = 0
    animation.duration = 60
    animation.isRemovedOnCompletion = false
    animation.fillMode = .forwards
    return animation
  }

  private static func basic(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    return animation
  }

  private static func spring(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, damping: CGFloat, velocity: CGFloat) -> CASpringAnimation {
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.mass = 5
    animation.stiffness = 900
    animation.damping = damping
    animation.initialVelocity = velocity
    animation.duration = animation.settlingDuration
    animation.speed = Float(animation.settlingDuration / duration)
    return animation
  }
}

#if DEBUG
private final class MorphProbe: NSObject {
  private let content: UIView
  private let dimming: [UIView]
  private let reverse: Bool
  private var link: CADisplayLink?
  private var samples: [[String: Any]] = []
  private var hierarchy: [[String: Any]] = []

  init(content: UIView, dimming: [UIView], reverse: Bool) {
    self.content = content
    self.dimming = dimming
    self.reverse = reverse
    super.init()
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify") else { return }
    func inspect(_ view: UIView, depth: Int) {
      hierarchy.append(["class": String(describing: type(of: view)), "depth": depth,
        "frame": NSCoder.string(for: view.frame), "alpha": view.alpha,
        "selected": dimming.contains { $0 === view }])
      if depth < 6 { view.subviews.forEach { inspect($0, depth: depth + 1) } }
    }
    if let window = content.window { inspect(window, depth: 0) }
    let link = CADisplayLink(target: self, selector: #selector(sample))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func sample() {
    let layer = content.layer.presentation() ?? content.layer
    samples.append(["scale": layer.transform.m11,
      "dimming": dimming.map { ($0.layer.presentation() ?? $0.layer).opacity }])
  }

  func stop() {
    guard link != nil else { return }
    link?.invalidate()
    link = nil
    let result: [String: Any] = ["reverse": reverse, "samples": samples, "hierarchy": hierarchy]
    if let data = try? JSONSerialization.data(withJSONObject: result) {
      try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lody-morph-\(UUID().uuidString).json"))
    }
  }
}
#endif

private extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
}
