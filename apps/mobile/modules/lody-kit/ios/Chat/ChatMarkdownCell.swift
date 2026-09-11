import UIKit

final class ChatMarkdownCell: UICollectionViewCell {
  private var markdown: ChatMarkdownView?
  private let icon = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private(set) var row: ChatRow?
  private var topInset = ChatRowPadding.content
  var onLink: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    icon.contentMode = .center
    contentView.addSubview(icon)
    contentView.addSubview(spinner)
    clipsToBounds = false
    contentView.clipsToBounds = false
    isAccessibilityElement = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ row: ChatRow, markdown: ChatMarkdownView, previousKind: String? = nil) {
    self.row = row
    topInset = ChatRowPadding.top(kind: row.kind, previousKind: previousKind)
    if self.markdown !== markdown {
      if self.markdown?.superview === contentView { self.markdown?.removeFromSuperview() }
      self.markdown = markdown
      contentView.addSubview(markdown)
    }
    markdown.onLink = { [weak self] in self?.onLink?($0) }
    icon.image = row.symbol.isEmpty ? nil : UIImage(systemName: row.symbol, withConfiguration: ChatCell.iconSymbolConfiguration(for: row))
    icon.tintColor = row.attention ? .systemOrange : .secondaryLabel
    row.running ? spinner.startAnimating() : spinner.stopAnimating()
    accessibilityIdentifier = row.id
    accessibilityLabel = row.text
    accessibilityCustomActions = markdown.fileActions
    accessibilityTraits = row.actionable ? .button : .staticText
    setNeedsLayout()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    row = nil
    topInset = ChatRowPadding.content
    if markdown?.superview === contentView {
      markdown?.onLink = nil
      markdown?.removeFromSuperview()
    }
    markdown = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let row, let markdown else { return }
    let width = contentView.bounds.width
    let inset = ChatCell.leading(row)
    let textWidth = ChatCell.textWidth(row, width: width)
    markdown.measure(width: textWidth)
    let height = markdown.measuredHeight
    markdown.frame = CGRect(x: inset, y: topInset, width: textWidth, height: height)
    icon.frame = ChatCell.iconFrame(for: row, textY: topInset, textHeight: height)
    spinner.frame = CGRect(x: width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
    var view: UIView? = superview
    while let current = view, !(current is UIScrollView) { view = current.superview }
    markdown.trackedScrollView = view as? UIScrollView
    clipsToBounds = false
    contentView.clipsToBounds = false
    layer.masksToBounds = false
    contentView.layer.masksToBounds = false
    ChatTableBleed.apply(to: markdown)
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if super.point(inside: point, with: event) { return true }
    guard let markdown else { return false }
    return markdown.point(inside: markdown.convert(point, from: self), with: event)
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if let markdown, let hit = markdown.hitTest(markdown.convert(point, from: self), with: event) {
      return hit
    }
    return super.hitTest(point, with: event)
  }
}
