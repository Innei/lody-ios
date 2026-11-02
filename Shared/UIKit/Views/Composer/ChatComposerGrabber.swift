import ObjectiveC
import UIKit

final class ChatComposerGrabber: UIView {
  static let height: CGFloat = 20
  var onToggle: (() -> Void)?
  var onPan: ((UIPanGestureRecognizer) -> Void)?
  private let handle = UIView()
  // Only a scroll view's pan drives the system's interactive keyboard dismissal; it stays transparent so its bounce never shows.
  // It rests mid-content because a sheet takes over pulls from a scroll view sitting at its top edge.
  private let track = UIScrollView()
  private static let trackRunway: CGFloat = 4000
  private var keyboardShift: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-grabber"
    isAccessibilityElement = true
    accessibilityTraits = .button
    track.alwaysBounceVertical = true
    track.scrollsToTop = false
    track.showsVerticalScrollIndicator = false
    track.keyboardDismissMode = .none
    track.frame = bounds
    track.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(track)
    handle.backgroundColor = .tertiaryLabel
    handle.layer.cornerRadius = 2.5
    handle.isUserInteractionEnabled = false
    handle.translatesAutoresizingMaskIntoConstraints = false
    addSubview(handle)
    NSLayoutConstraint.activate([
      handle.centerXAnchor.constraint(equalTo: centerXAnchor),
      handle.centerYAnchor.constraint(equalTo: centerYAnchor),
      handle.widthAnchor.constraint(equalToConstant: 36),
      handle.heightAnchor.constraint(equalToConstant: 5),
    ])
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    ChatComposerKeyboardTouch.install(on: track.panGestureRecognizer)
    track.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = CGSize(width: bounds.width, height: bounds.height + Self.trackRunway * 2)
    guard track.contentSize != size else { return }
    track.contentSize = size
    recenterTrack()
  }

  private func recenterTrack() {
    track.contentOffset = CGPoint(x: 0, y: Self.trackRunway)
  }

  func followKeyboard(fromTouchY touchY: CGFloat, keyboardTop: CGFloat, keepsKeyboard: @escaping (_ translation: CGFloat, _ velocity: CGFloat) -> Bool) {
    keyboardShift = keyboardTop - touchY
    ChatComposerKeyboardTouch.shift = keyboardShift
    ChatComposerKeyboardTouch.keepsKeyboard = keepsKeyboard
    ChatComposerKeyboardTouch.translation = 0
    track.keyboardDismissMode = .interactive
  }

  func updateKeyboard(shrinkingBy height: CGFloat) {
    // The panel's lost height already moves its top down. Give only the remaining
    // finger travel to the keyboard so both movements add up to the same drag.
    ChatComposerKeyboardTouch.shift = keyboardShift - height
  }

  func releaseKeyboard() {
    ChatComposerKeyboardTouch.shift = 0
    ChatComposerKeyboardTouch.keepsKeyboard = nil
    track.keyboardDismissMode = .none
  }

  override func accessibilityActivate() -> Bool {
    onToggle?()
    return true
  }

  @objc private func tap() { onToggle?() }
  @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
    switch recognizer.state {
    case .changed: ChatComposerKeyboardTouch.translation = recognizer.translation(in: nil).y
    case .ended, .cancelled, .failed: recenterTrack()
    default: break
    }
    onPan?(recognizer)
  }
}

// The system keyboard picks up an interactive dismissal only once the finger reaches its top edge.
// Reporting the grabber's touches shifted onto that edge makes it follow from the first point of the drag.
// The system also dismisses whenever the finger lifts while moving down, so a release the composer
// springs back from reports an upward lift instead. If UIKit stops reading these methods, the keyboard
// falls back to joining when the finger reaches it and to the system's own release decision.
@MainActor
enum ChatComposerKeyboardTouch {
  nonisolated(unsafe) static var shift: CGFloat = 0
  nonisolated(unsafe) static var keepsKeyboard: ((CGFloat, CGFloat) -> Bool)?
  nonisolated(unsafe) static var translation: CGFloat = 0

  static func install(on pan: UIPanGestureRecognizer) {
    guard let base = object_getClass(pan) else { return }
    let name = "LodyKeyboardTouch_" + NSStringFromClass(base)
    if let existing = NSClassFromString(name) {
      object_setClass(pan, existing)
      return
    }
    let locationSelector = #selector(UIGestureRecognizer.location(ofTouch:in:))
    let velocitySelector = #selector(UIPanGestureRecognizer.velocity(in:))
    guard let locationMethod = class_getInstanceMethod(base, locationSelector),
          let velocityMethod = class_getInstanceMethod(base, velocitySelector),
          let made = objc_allocateClassPair(base, name, 0) else { return }
    typealias Location = @convention(c) (AnyObject, Selector, Int, UIView?) -> CGPoint
    typealias Velocity = @convention(c) (AnyObject, Selector, UIView?) -> CGPoint
    let location = unsafeBitCast(method_getImplementation(locationMethod), to: Location.self)
    let velocity = unsafeBitCast(method_getImplementation(velocityMethod), to: Velocity.self)
    func keeps(_ recognizer: AnyObject) -> Bool {
      guard let pan = recognizer as? UIPanGestureRecognizer, let keepsKeyboard,
            pan.state == .ended || pan.state == .cancelled else { return false }
      let speed = velocity(recognizer, velocitySelector, nil).y
      return keepsKeyboard(translation, speed)
    }
    let shiftedLocation: @convention(block) (AnyObject, Int, UIView?) -> CGPoint = { recognizer, index, view in
      var point = location(recognizer, locationSelector, index, view)
      point.y += keeps(recognizer) ? 0 : shift
      return point
    }
    let releasedVelocity: @convention(block) (AnyObject, UIView?) -> CGPoint = { recognizer, view in
      var speed = velocity(recognizer, velocitySelector, view)
      if keeps(recognizer) { speed.y = -max(1, abs(speed.y)) }
      return speed
    }
    class_addMethod(made, locationSelector, imp_implementationWithBlock(shiftedLocation), method_getTypeEncoding(locationMethod))
    class_addMethod(made, velocitySelector, imp_implementationWithBlock(releasedVelocity), method_getTypeEncoding(velocityMethod))
    objc_registerClassPair(made)
    object_setClass(pan, made)
  }
}
