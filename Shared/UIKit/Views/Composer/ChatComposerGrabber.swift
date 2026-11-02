import UIKit

final class ChatComposerGrabber: UIView {
  static let height: CGFloat = 20
  var onToggle: (() -> Void)?
  var onPan: ((UIPanGestureRecognizer) -> Void)?
  var onKeyboardDismiss: ((TimeInterval, UIView.AnimationOptions) -> Void)?
  var onKeyboardReturn: ((TimeInterval, UIView.AnimationOptions) -> Void)?
  var onKeyboardHidden: (() -> Void)?
  private let handle = UIView()
  // Only a scroll view's pan drives the system's interactive keyboard dismissal; it stays transparent so its bounce never shows.
  // It rests mid-content because a sheet takes over pulls from a scroll view sitting at its top edge.
  private let track = UIScrollView()
  private static let trackRunway: CGFloat = 4000
  private weak var keyboardGuide: UIKeyboardLayoutGuide?
  private weak var preparedGuide: UIKeyboardLayoutGuide?
  private var keyboardPadding: CGFloat = 0
  private var previousKeyboardPadding: CGFloat = 0
  private var panning = false

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
    track.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  isolated deinit { NotificationCenter.default.removeObserver(self) }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = CGSize(width: bounds.width, height: Self.height + Self.trackRunway * 2)
    guard track.contentSize != size else { return }
    track.contentSize = size
    if !panning && keyboardGuide == nil { recenterTrack() }
  }

  private func recenterTrack() {
    track.contentOffset = CGPoint(x: 0, y: Self.trackRunway)
  }

  func prepareKeyboard(guide: UIKeyboardLayoutGuide, padding: CGFloat, enabled: Bool) {
    guard keyboardGuide == nil else { return }
    guard enabled else { releaseKeyboard(); return }
    if preparedGuide !== guide {
      preparedGuide?.keyboardDismissPadding = previousKeyboardPadding
      previousKeyboardPadding = guide.keyboardDismissPadding
      preparedGuide = guide
    }
    guide.keyboardDismissPadding = max(0, padding)
    // UIKit must see interactive dismissal when the gesture begins, rather than
    // being switched into it from our later pan target.
    track.keyboardDismissMode = .interactive
  }

  func followKeyboard(guide: UIKeyboardLayoutGuide, fromTouchY touchY: CGFloat, keyboardTop: CGFloat) {
    keyboardGuide = guide
    if preparedGuide !== guide { previousKeyboardPadding = guide.keyboardDismissPadding }
    keyboardPadding = guide.keyboardDismissPadding
    if keyboardPadding <= 0 { keyboardPadding = max(0, keyboardTop - touchY) }
    guide.keyboardDismissPadding = keyboardPadding
    track.keyboardDismissMode = .interactive
  }

  func updateKeyboard(shrinkingBy height: CGFloat) {
    // The panel's lost height already moves its top down. Give only the remaining
    // finger travel to the keyboard so both movements add up to the same drag.
    keyboardGuide?.keyboardDismissPadding = max(0, keyboardPadding - height)
  }

  func releaseKeyboard() {
    (preparedGuide ?? keyboardGuide)?.keyboardDismissPadding = previousKeyboardPadding
    preparedGuide = nil
    keyboardGuide = nil
    track.keyboardDismissMode = .none
    if !panning { recenterTrack() }
  }

  @objc private func keyboardDidHide() {
    guard keyboardGuide != nil else { return }
    onKeyboardHidden?()
  }

  private func animation(_ notification: Notification) -> (TimeInterval, UIView.AnimationOptions) {
    let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
    let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
    return (duration, UIView.AnimationOptions(rawValue: curve << 16).union([.beginFromCurrentState, .allowUserInteraction]))
  }

  @objc private func keyboardWillHide(_ notification: Notification) {
    guard keyboardGuide != nil else { return }
    let (duration, options) = animation(notification)
    onKeyboardDismiss?(duration, options)
  }

  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    guard let host = keyboardGuide?.owningView, let screen = host.window?.windowScene?.screen,
      let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    let local = host.convert(frame, from: screen.coordinateSpace)
    let (duration, options) = animation(notification)
    if local.minY < host.bounds.maxY - host.safeAreaInsets.bottom - 1 {
      onKeyboardReturn?(duration, options)
    } else {
      onKeyboardDismiss?(duration, options)
    }
  }

  override func accessibilityActivate() -> Bool {
    onToggle?()
    return true
  }

  @objc private func tap() { onToggle?() }
  @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
    panning = recognizer.state == .began || recognizer.state == .changed
    onPan?(recognizer)
    if !panning && track.keyboardDismissMode != .interactive { recenterTrack() }
  }
}
