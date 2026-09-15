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
  private static var sourceLabel: String?

  static func prepare(sourceLabel: String) {
    cancel()
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return }
    self.sourceLabel = sourceLabel
    let source = findSource(label: sourceLabel, from: root)
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
        let dimming = presented.presentationController?.containerView?.subviews.first {
          $0 !== sheet && String(describing: type(of: $0)).contains("Dimming")
        }
        dimming?.alpha = 0
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
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return completion() }
    var presented = root
    while let next = presented.presentedViewController { presented = next }
    guard presented !== root, presented.sheetPresentationController != nil,
      let sheet = presented.presentationController?.presentedView,
      let label = sourceLabel, let source = findSource(label: label, from: root)
    else { return completion() }
    let dimming = presented.presentationController?.containerView?.subviews.first {
      $0 !== sheet && String(describing: type(of: $0)).contains("Dimming")
    }
    presented.view.isUserInteractionEnabled = false
    morph(presented: presented, sheet: sheet, dimming: dimming, source: source, reverse: true) {
      presented.view.alpha = 0
      dimming?.alpha = 0
      completion()
    }
  }

  private static func reveal(presented: UIViewController, sheet: UIView, dimming: UIView?, source: UIView?) {
    let content = presented.view!
    content.layer.removeAnimation(forKey: "morphHold")
    sheet.mask = nil
    if let dimming {
      dimming.alpha = 1
      dimming.layer.add(basic("opacity", from: 0, to: 1, duration: 0.3), forKey: "morph")
    }
    guard let source, source.window != nil, source.bounds.width > 0 else {
      content.layer.add(basic("opacity", from: 0, to: 1, duration: 0.2), forKey: "morph")
      return
    }
    morph(presented: presented, sheet: sheet, dimming: nil, source: source, reverse: false) {}
  }

  private static func morph(presented: UIViewController, sheet: UIView, dimming: UIView?, source: UIView, reverse: Bool, completion: @escaping () -> Void) {
    guard let container = presented.presentationController?.containerView else { return completion() }
    let content = presented.view!
    container.layoutIfNeeded()
    let targetFrame = sheet.convert(sheet.bounds, to: container)
    let sourceFrame = source.convert(source.bounds, to: container)
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
    dimming?.layer.add(basic("opacity", 0, 1, 0.3), forKey: "morphOpacity")
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
      completion()
      sheet.mask = reverse ? UIView() : nil
      sheet.layer.shadowOpacity = shadowOpacity
      iconCarrier.removeFromSuperview()
      source.isHidden = false
      if reverse {
        for layer in [content.layer, dimming?.layer] { layer?.removeAllAnimations() }
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

private extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
}
