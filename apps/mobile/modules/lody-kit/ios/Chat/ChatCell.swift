import UIKit

final class ChatCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
  var messageContent = ChatMessageContent(frame: .zero)
  var label: ChatTextView { messageContent.label }
  var bubble: UIView { messageContent.bubble }
  let icon = UIImageView()
  let spinner = UIActivityIndicatorView(style: .medium)
  var row: ChatRow?
  var onInteraction: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    bubble.backgroundColor = .lodyUserBubble
    bubble.layer.cornerRadius = 19
    bubble.layer.cornerCurve = .continuous
    contentView.addSubview(messageContent)
    contentView.addSubview(icon)
    contentView.addSubview(spinner)
    icon.contentMode = .center
    isAccessibilityElement = true
    contentView.addInteraction(UIContextMenuInteraction(delegate: self))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func configure(_ row: ChatRow, text: NSAttributedString) {
    label.setText(text, animate: row.streaming, reset: self.row?.id != row.id)
    self.row = row
    if row.kind == "user" { ChatSendHandoff.hold(id: row.entryID, target: messageContent) }
    else { messageContent.isHidden = false }
    bubble.isHidden = row.kind != "user"
    icon.image = row.symbol.isEmpty ? nil : UIImage(systemName: row.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
    icon.tintColor = chromeColor(for: row)
    row.running && row.kind != "summary" ? spinner.startAnimating() : spinner.stopAnimating()
    accessibilityIdentifier = row.id
    accessibilityLabel = text.string
    accessibilityTraits = row.actionable ? .button : .staticText
    accessibilityHint = hint(for: row)
    label.setShine(row.kind == "summary" && row.running && !row.attention)
    setNeedsLayout()
  }
  func adopt(_ content: ChatMessageContent) {
    let frame = messageContent.frame
    messageContent.removeFromSuperview()
    messageContent = content
    contentView.insertSubview(content, at: 0)
    content.frame = frame
    content.isHidden = false
    content.isUserInteractionEnabled = true
    content.accessibilityElementsHidden = false
    setNeedsLayout()
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    label.setShine(false)
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard let row, row.kind == "user", messageContent.frame.contains(location) else { return nil }
    onInteraction?()
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(children: [UIAction(title: LodyStrings.text("native.chat.copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
        UIPasteboard.general.string = row.text
      }])
    }
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                             previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    contextPreview()
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                             previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    contextPreview()
  }

  private func contextPreview() -> UITargetedPreview? {
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .lodyUserBubble
    let rect = messageContent.frame
    guard let preview = contentView.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
    parameters.visiblePath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: 19)
    return UITargetedPreview(view: preview, parameters: parameters,
      target: UIPreviewTarget(container: contentView, center: CGPoint(x: rect.midX, y: rect.midY)))
  }

  static func leading(_ row: ChatRow) -> CGFloat {
    row.kind == "text" || row.kind == "user" ? 0 : 24
  }
  static func textWidth(_ row: ChatRow, width: CGFloat) -> CGFloat {
    // Reserve the status slot even after completion: status cannot rewrap text.
    let reserved: CGFloat = row.kind == "text" || row.kind == "thought" || row.kind == "summary" ? 0 : 28
    if row.kind == "user" { return max(1, width * 0.84 - 26) }
    return max(1, width - leading(row) - reserved)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let row else { return }
    let width = contentView.bounds.width
    if row.kind == "user" {
      let size = label.sizeThatFits(CGSize(width: width * 0.84 - 26, height: .greatestFiniteMagnitude))
      messageContent.frame = CGRect(x: width - size.width - 26, y: 12, width: size.width + 26, height: size.height + 20)
      messageContent.layoutIfNeeded()
    } else {
      messageContent.frame = contentView.bounds
      messageContent.layoutIfNeeded()
      let inset = Self.leading(row)
      let textWidth = Self.textWidth(row, width: width)
      let height = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
      let y = row.kind == "text" || row.kind == "thought" ? 6 : max(6, (bounds.height - height) / 2)
      label.frame = CGRect(x: inset, y: y, width: textWidth, height: height)
      icon.frame = CGRect(x: 0, y: y, width: 16, height: min(height, 20))
    }
    spinner.frame = CGRect(x: width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    bubble.backgroundColor = .lodyUserBubble
  }
}

private func chromeColor(for row: ChatRow) -> UIColor {
  if row.attention { return .systemOrange }
  if row.kind == "changes" || (row.kind == "summary" && row.running) { return .systemBlue }
  return .secondaryLabel
}

private func hint(for row: ChatRow) -> String? {
  if row.id == row.entryID + ":pending" {
    return row.actionable ? LodyStrings.text("native.chat.row.resend") : nil
  }
  switch row.kind {
  case "summary": return LodyStrings.text("native.chat.row.openProcess")
  case "changes": return LodyStrings.text("native.chat.row.openChanges")
  default: return nil
  }
}
