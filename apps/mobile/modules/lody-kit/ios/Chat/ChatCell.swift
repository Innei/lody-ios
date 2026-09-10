import UIKit

enum ChatRowPadding {
  static let content: CGFloat = 6
  static var durationBottom: CGFloat { content / 2 }
}

final class ChatMetaCell: UICollectionViewCell {
  private let copyButton = UIButton(type: .system)
  private let modelLabel = UILabel()
  private var copyText: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    modelLabel.numberOfLines = 0
    modelLabel.textAlignment = .right
    modelLabel.textColor = .secondaryLabel
    modelLabel.adjustsFontForContentSizeCategory = true
    copyButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 15), forImageIn: .normal)
    copyButton.addTarget(self, action: #selector(copyAnswer), for: .touchUpInside)
    contentView.addSubview(copyButton)
    contentView.addSubview(modelLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ row: ChatRow) {
    copyText = row.copyText
    copyButton.isHidden = row.copyText == nil
    copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
    copyButton.accessibilityLabel = LodyStrings.text("native.chat.copy")
    copyButton.accessibilityIdentifier = row.id + ":copy"
    modelLabel.text = row.text
    modelLabel.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    modelLabel.isHidden = row.text.isEmpty
    modelLabel.accessibilityIdentifier = row.id + ":model"
    setNeedsLayout()
  }

  @objc private func copyAnswer() {
    guard let copyText else { return }
    UIPasteboard.general.string = copyText
    copyButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
    copyButton.accessibilityLabel = LodyStrings.text("native.chat.copied")
    UIAccessibility.post(notification: .announcement, argument: LodyStrings.text("native.chat.copied"))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    copyButton.frame = CGRect(x: 0, y: (bounds.height - 44) / 2, width: 44, height: 44)
    let leading: CGFloat = copyButton.isHidden ? 0 : 52
    modelLabel.frame = CGRect(x: leading, y: 4, width: max(1, bounds.width - leading), height: bounds.height - 8)
  }

  static func height(for row: ChatRow, width: CGFloat, traits: UITraitCollection) -> CGFloat {
    let textWidth = max(1, width - (row.copyText == nil ? 0 : 52))
    let font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
    let textHeight = (row.text as NSString).boundingRect(
      with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
    ).height
    return max(44, ceil(textHeight) + 8)
  }
}

final class ChatCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
  let messageContent = ChatMessageContent(frame: .zero)
  var label: ChatTextView { messageContent.label }
  var bubble: UIView { messageContent.bubble }
  let icon = UIImageView()
  let spinner = UIActivityIndicatorView(style: .medium)
  let separator = UIView()
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
    contentView.addSubview(separator)
    icon.contentMode = .center
    separator.backgroundColor = .separator
    separator.isHidden = true
    separator.isUserInteractionEnabled = false
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
    icon.image = row.symbol.isEmpty ? nil : UIImage(systemName: row.symbol, withConfiguration: Self.iconSymbolConfiguration(for: row))
    icon.tintColor = chromeColor(for: row)
    row.running && row.kind != "summary" && row.kind != "duration"
      ? spinner.startAnimating()
      : spinner.stopAnimating()
    separator.isHidden = row.kind != "duration"
    accessibilityIdentifier = row.id
    accessibilityLabel = text.string
    accessibilityTraits = row.actionable ? .button : .staticText
    accessibilityHint = hint(for: row)
    label.setShine(row.shines)
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

  static func messageFont(for row: ChatRow, compatibleWith traits: UITraitCollection) -> UIFont {
    let font = UIFont.dynamic(of: row.kind == "user" ? 17 : 13, compatibleWith: traits)
    if row.kind == "duration" || row.kind == "summary" {
      return font.withTabularNumbers()
    }
    return font
  }

  static func rowExtra(for row: ChatRow) -> CGFloat {
    if row.kind == "user" { return 44 }
    if row.kind == "duration" { return ChatRowPadding.content + ChatRowPadding.durationBottom }
    return ChatRowPadding.content * 2
  }

  static func leading(_ row: ChatRow) -> CGFloat {
    switch row.kind {
    case "text", "user", "duration": return 0
    case "summary": return 12
    default: return 24
    }
  }
  static func iconSymbolConfiguration(for row: ChatRow) -> UIImage.SymbolConfiguration {
    if row.kind == "summary" {
      return UIImage.SymbolConfiguration(pointSize: 6)
    }
    if row.kind == "thought" {
      return UIImage.SymbolConfiguration(pointSize: 13, weight: .regular, scale: .small)
    }
    return UIImage.SymbolConfiguration(pointSize: 13)
  }
  static func iconFrame(for row: ChatRow, textY: CGFloat, textHeight: CGFloat) -> CGRect {
    if row.kind == "summary" {
      let size: CGFloat = 8
      return CGRect(x: 0, y: textY + (textHeight - size) / 2, width: size, height: size)
    }
    return CGRect(x: 2, y: textY, width: 20, height: min(textHeight, 20))
  }
  static func textWidth(_ row: ChatRow, width: CGFloat) -> CGFloat {
    // Reserve the status slot even after completion: status cannot rewrap text.
    let reserved: CGFloat =
      row.kind == "text" || row.kind == "thought" || row.kind == "summary" || row.kind == "duration"
        ? 0
        : 28
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
      let y: CGFloat
      if row.kind == "text" || row.kind == "thought" || row.kind == "duration" {
        y = ChatRowPadding.content
      } else {
        y = max(ChatRowPadding.content, (bounds.height - height) / 2)
      }
      label.frame = CGRect(x: inset, y: y, width: textWidth, height: height)
      let markHeight = row.kind == "summary"
        ? (label.lineAdvances(width: textWidth).first ?? height)
        : height
      icon.frame = Self.iconFrame(for: row, textY: y, textHeight: markHeight)
    }
    spinner.frame = CGRect(x: width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
    let pixel = 1 / max(1, traitCollection.displayScale)
    separator.frame = CGRect(x: 0, y: contentView.bounds.height - pixel, width: width, height: pixel)
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
