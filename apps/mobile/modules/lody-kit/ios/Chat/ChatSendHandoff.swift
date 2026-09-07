import UIKit

/// The content moves; collection cells keep their own reuse lifecycle.
final class ChatMessageContent: UIView {
  let label = ChatTextView()
  let bubble = UIView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    bubble.backgroundColor = .lodyUserBubble
    bubble.layer.cornerRadius = 19
    bubble.layer.cornerCurve = .continuous
    addSubview(bubble)
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() {
    super.layoutSubviews()
    bubble.frame = bounds
    bubble.backgroundColor = .lodyUserBubble
    // Process rows own the label frame so the chevron keeps its 8pt gap.
    // Bubble insets are only for the user send handoff.
    guard !bubble.isHidden else { return }
    UIView.performWithoutAnimation {
      label.frame = bounds.insetBy(dx: 13, dy: 10)
      label.layer.displayIfNeeded()
    }
  }
}

final class ChatSendHandoff {
  private static var active: [String: ChatSendHandoff] = [:]
  let content = ChatMessageContent(frame: .zero)
  private var expiry: DispatchWorkItem?
  private var photo: UIImageView?
  private var delivering = false
  private weak var target: UIView?

  static func hold(id: String, target: UIView) {
    guard let handoff = active[id] else { target.isHidden = false; return }
    handoff.target = target
    target.isHidden = true
  }

  static func begin(id: String, text: String, source: UIView) {
    guard let window = source.window else { return }
    let handoff = ChatSendHandoff()
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = 25 * UIFont.dynamicScale(compatibleWith: source.traitCollection)
    paragraph.maximumLineHeight = paragraph.minimumLineHeight
    let font = UIFont.dynamic(of: 17, compatibleWith: source.traitCollection)
    handoff.content.label.setText(NSAttributedString(string: text, attributes: [
      .paragraphStyle: paragraph,
      .font: font,
      .foregroundColor: UIColor.label,
      .baselineOffset: (paragraph.minimumLineHeight - font.lineHeight) / 2,
    ]))
    handoff.content.frame = source.convert(source.bounds, to: window)
    handoff.content.isUserInteractionEnabled = false
    handoff.content.accessibilityElementsHidden = true
    window.addSubview(handoff.content)
    active[id] = handoff
    let expiry = DispatchWorkItem { cancel(id: id) }
    handoff.expiry = expiry
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
  }

  static func beginImages(id: String, attachments: [ChatAttachment], source: ChatAttachmentBar) {
    guard let window = source.window else { return }
    for attachment in attachments where attachment.isImage {
      guard let image = ChatAttachment.thumbnail(attachment.url) else { continue }
      let handoff = ChatSendHandoff()
      let photo = UIImageView(image: image)
      photo.contentMode = .scaleAspectFit
      photo.clipsToBounds = true
      photo.layer.cornerRadius = 16
      let sourceFrame = source.convert(source.attachmentFrame(id: attachment.id) ?? source.bounds, to: window)
      let side = min(42, sourceFrame.height)
      photo.frame = CGRect(x: sourceFrame.minX + 11, y: sourceFrame.minY, width: side, height: side)
      photo.isUserInteractionEnabled = false
      photo.accessibilityElementsHidden = true
      handoff.photo = photo
      window.addSubview(photo)
      let key = id + ":image:" + attachment.id
      active[key] = handoff
      let expiry = DispatchWorkItem { cancel(id: key) }
      handoff.expiry = expiry
      DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
    }
  }

  static func deliverImage(id: String, attachmentID: String, to target: UIImageView, adopt: @escaping (UIImageView) -> Void) {
    let key = id + ":image:" + attachmentID
    guard let window = target.window, let handoff = active[key], !handoff.delivering, let photo = handoff.photo else { return }
    handoff.delivering = true
    handoff.target = target
    handoff.expiry?.cancel()
    let destination = target.convert(target.bounds, to: window)
    target.isHidden = true
    let finish = {
      target.isHidden = false
      guard active[key] === handoff else { photo.removeFromSuperview(); return }
      active.removeValue(forKey: key)
      adopt(photo)
    }
    if UIAccessibility.isReduceMotionEnabled { finish(); return }
    UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
      photo.frame = destination
    } completion: { _ in finish() }
  }

  static func cancel(id: String) {
    for key in active.keys.filter({ $0.hasPrefix(id + ":image:") }) { cancel(id: key) }
    guard let handoff = active.removeValue(forKey: id) else { return }
    handoff.expiry?.cancel()
    handoff.target?.isHidden = false
    handoff.photo?.layer.removeAllAnimations()
    handoff.content.layer.removeAllAnimations()
    handoff.content.removeFromSuperview()
    handoff.photo?.removeFromSuperview()
  }

  static func deliver(id: String, to target: ChatMessageContent, adopt: @escaping (ChatMessageContent) -> Void) {
    guard let window = target.window, let handoff = active[id], !handoff.delivering else { return }
    handoff.delivering = true
    handoff.target = target
    handoff.expiry?.cancel()
    let destination = target.convert(target.bounds, to: window)
    handoff.content.label.setText(target.label.attributedTextValue)
    target.isHidden = true
    let finish = {
      target.isHidden = false
      guard active[id] === handoff else { handoff.content.removeFromSuperview(); return }
      active.removeValue(forKey: id)
      adopt(handoff.content)
    }
    if UIAccessibility.isReduceMotionEnabled { finish(); return }
    UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
      handoff.content.frame = destination
      handoff.content.layoutIfNeeded()
    } completion: { _ in finish() }
  }
}
