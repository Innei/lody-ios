import ExpoModulesCore
import UIKit

/// Morphs the next sheet presentation out of a bar button, Telegram
/// attachment-menu style. Armed right before JS presents a sheet without
/// animation; the patched native stack posts `RNSScreenStackDidPresentModal`
/// synchronously inside the presenting call, so the sheet is hidden before
/// its first frame commits. Only presentation-layer animations run afterwards
/// so the sheet controller's own layout never conflicts.
@MainActor
enum LodyMorphReveal {
  private static var token: NSObjectProtocol?
  private static var observer: CFRunLoopObserver?
  private static var timeout: DispatchWorkItem?
  private static weak var hidden: UIView?

  static func prepare(sourceLabel: String) {
    cancel()
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return }
    let source = findSource(label: sourceLabel, from: root)
    token = NotificationCenter.default.addObserver(
      forName: Notification.Name("RNSScreenStackDidPresentModal"), object: nil, queue: nil
    ) { notification in
      nonisolated(unsafe) let object = notification.object
      MainActor.assumeIsolated {
        guard let presented = object as? UIViewController, presented.sheetPresentationController != nil else { return }
        // Fabric has applied the screen's props by now, so this sticks. UIKit
        // builds the sheet wrapper on a later turn; it is masked as soon as
        // it exists, before that turn's commit.
        presented.view.alpha = 0
        hidden = presented.view
        if let token {
          NotificationCenter.default.removeObserver(token)
          self.token = nil
        }
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
          guard presented.view.window != nil, let sheet = presented.presentationController?.presentedView else { return }
          cancel()
          sheet.mask = UIView()
          let dimming = presented.presentationController?.containerView?.subviews.first {
            $0 !== sheet && String(describing: type(of: $0)).contains("Dimming")
          }
          dimming?.alpha = 0
          DispatchQueue.main.async { reveal(presented: presented, sheet: sheet, dimming: dimming, source: source) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
      }
    }
    let timeout = DispatchWorkItem {
      hidden?.alpha = 1
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
    if let observer {
      CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
      self.observer = nil
    }
  }

  private static func reveal(presented: UIViewController, sheet: UIView, dimming: UIView?, source: UIView?) {
    let content = presented.view!
    content.alpha = 1
    sheet.mask = nil
    if let dimming {
      dimming.alpha = 1
      dimming.layer.add(basic("opacity", from: 0, to: 1, duration: 0.3), forKey: "morph")
    }
    guard let container = presented.presentationController?.containerView,
      let source, source.window != nil, source.bounds.width > 0
    else {
      content.layer.add(basic("opacity", from: 0, to: 1, duration: 0.2), forKey: "morph")
      return
    }
    container.layoutIfNeeded()
    let targetFrame = sheet.convert(sheet.bounds, to: container)
    let sourceFrame = source.convert(source.bounds, to: container)
    let scale = sourceFrame.width / targetFrame.width
    let square = CGRect(x: 0, y: 0, width: sheet.bounds.width, height: sheet.bounds.width)
    let cornerRadius: CGFloat = 38

    let iconCarrier = UIView(frame: targetFrame)
    let icon = UIImageView(image: UIImage(systemName: "plus"))
    icon.preferredSymbolConfiguration = .init(pointSize: 17, weight: .semibold)
    icon.tintColor = source.tintColor
    icon.sizeToFit()
    icon.center = CGPoint(x: targetFrame.width / 2, y: targetFrame.height / 2)
    icon.transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
    icon.alpha = 0
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
    let carrierPosition = spring("position", from: NSValue(cgPoint: sourceFrame.center), to: NSValue(cgPoint: targetFrame.center), duration: 0.4, velocity: 1.1)
    let sourceCenter = container.convert(sourceFrame.center, to: sheet)
    let contentPosition = spring("position", from: NSValue(cgPoint: sourceCenter), to: NSValue(cgPoint: content.layer.position), duration: 0.4, velocity: 1.1)
    let maskPosition = spring("position", from: NSValue(cgPoint: sourceCenter), to: NSValue(cgPoint: mask.layer.position), duration: 0.4, velocity: 1.1)
    let scaleAnimation = spring("transform", from: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)), to: NSValue(caTransform3D: CATransform3DIdentity), duration: 0.45, velocity: 0)
    let maskBounds = spring("bounds", from: NSValue(cgRect: square), to: NSValue(cgRect: mask.bounds), duration: 0.45, velocity: 0)
    let corners = basic("cornerRadius", from: targetFrame.width / 2, to: cornerRadius, duration: 0.2)
    corners.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    iconCarrier.layer.add(carrierPosition, forKey: "morphPosition")
    iconCarrier.layer.add(scaleAnimation, forKey: "morphScale")
    content.layer.add(contentPosition, forKey: "morphPosition")
    content.layer.add(scaleAnimation, forKey: "morphScale")
    content.layer.add(basic("opacity", from: 0, to: 1, duration: 0.2), forKey: "morphOpacity")
    mask.layer.add(maskPosition, forKey: "morphPosition")
    mask.layer.add(scaleAnimation, forKey: "morphScale")
    mask.layer.add(maskBounds, forKey: "morphBounds")
    mask.layer.add(corners, forKey: "morphCorners")
    icon.layer.add(basic("opacity", from: 1, to: 0, duration: 0.15), forKey: "morphOpacity")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      sheet.mask = nil
      sheet.layer.shadowOpacity = shadowOpacity
      iconCarrier.removeFromSuperview()
      source.isHidden = false
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

  private static func basic(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    return animation
  }

  private static func spring(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, velocity: CGFloat) -> CASpringAnimation {
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.mass = 5
    animation.stiffness = 900
    animation.damping = 110
    animation.initialVelocity = velocity
    animation.duration = animation.settlingDuration
    animation.speed = Float(animation.settlingDuration / duration)
    return animation
  }
}

private extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
}
