import ExpoModulesCore
import UIKit

/// Standalone host for the same input used by LodyChatView, including sheet keyboard clearance.
final class LodyComposerView: ExpoView {
  let onSend = EventDispatcher()
  let onHeightChange = EventDispatcher()
  let onComposerOptionChange = EventDispatcher()
  let onMentionBrowse = EventDispatcher()
  let composer = ChatComposerView(frame: .zero)
  private var contentHeight: CGFloat = 64
  private var reportedHeight: CGFloat = 0
  var scrollEdge = false { didSet { setNeedsLayout() } }
  private var keyboardFrame: CGRect = .null

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    reportHeight()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    reportHeight()
    attachScrollEdge()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { composer.attachScrollEdge(to: nil) }
    else { setNeedsLayout() }
  }

  private func attachScrollEdge() {
    guard scrollEdge, window != nil else {
      composer.attachScrollEdge(to: nil)
      return
    }
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController,
         let scrollView = controller.contentScrollView(for: .bottom) {
        composer.attachScrollEdge(to: scrollView)
        return
      }
      responder = current.next
    }
  }

  private func reportHeight() {
    // Keyboard frames use screen coordinates; RN sheet layout uses local coordinates.
    // Measure the host's actual overlap so sheet detents and its inner header cannot
    // leave the send row under the prediction bar.
    let keyboard = window.map { convert($0.convert(keyboardFrame, from: nil), from: $0) } ?? .null
    let overlap = keyboard.intersects(bounds) ? max(0, bounds.maxY - keyboard.minY) : 0
    let height = contentHeight + (overlap > 0 ? overlap : max(16, safeAreaInsets.bottom))
    guard height != reportedHeight else { return }
    reportedHeight = height
    onHeightChange(["height": height])
  }

  @objc private func keyboardChanged(_ notification: Notification) {
    keyboardFrame = notification.name == UIResponder.keyboardWillHideNotification
      ? .null
      : (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null)
    reportHeight()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillHideNotification, object: nil)
    composer.setInputIdentifier("create-session-input")
    composer.onSend = { [weak self] in self?.onSend($0) }
    composer.onHeightChange = { [weak self] height in
      self?.contentHeight = height
      self?.reportHeight()
    }
    composer.onMentionBrowse = { [weak self] in self?.onMentionBrowse($0) }
    composer.onComposerOptionChange = { [weak self] in self?.onComposerOptionChange($0) }
    addSubview(composer)
    composer.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      composer.topAnchor.constraint(equalTo: topAnchor),
      composer.leadingAnchor.constraint(equalTo: leadingAnchor),
      composer.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }
}
