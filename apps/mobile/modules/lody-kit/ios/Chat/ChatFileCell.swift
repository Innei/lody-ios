import UIKit

final class ChatFileCell: UICollectionViewListCell {
  private let chrome = UIView()
  private let separator = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    automaticallyUpdatesBackgroundConfiguration = false
    backgroundConfiguration = .clear()
    chrome.isUserInteractionEnabled = false
    chrome.layer.cornerCurve = .continuous
    chrome.layer.masksToBounds = true
    insertSubview(chrome, belowSubview: contentView)
    separator.backgroundColor = .separator
    contentView.addSubview(separator)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(group: String, selected: Bool) {
    backgroundConfiguration = .clear()
    chrome.backgroundColor = selected ? .lodyFileGroupSelected : .lodyFileGroup
    chrome.layer.cornerRadius = group == "middle" ? 0 : 12
    switch group {
    case "first":
      chrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    case "last":
      chrome.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    case "middle":
      chrome.layer.maskedCorners = []
    default:
      chrome.layer.maskedCorners = [
        .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
      ]
    }
    separator.isHidden = group == "last" || group == "only" || group.isEmpty
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    chrome.frame = bounds
    let scale = max(traitCollection.displayScale, 1)
    let inset = directionalLayoutMargins.leading + 36
    separator.frame = CGRect(
      x: inset,
      y: bounds.height - 1 / scale,
      width: max(0, bounds.width - inset - 16),
      height: 1 / scale
    )
  }

  static func rowContent() -> UIListContentConfiguration {
    var content = UIListContentConfiguration.subtitleCell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingMiddle
    content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
    content.secondaryTextProperties.color = .secondaryLabel
    content.secondaryTextProperties.numberOfLines = 1
    content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
    content.image = UIImage(systemName: "doc.text")
    content.imageProperties.tintColor = .secondaryLabel
    content.imageProperties.preferredSymbolConfiguration = .init(textStyle: .body)
    return content
  }

  static func rowHeight() -> CGFloat {
    var content = rowContent()
    content.text = "Filename"
    content.secondaryText = "path"
    let view = UIListContentView(configuration: content)
    let height = view.systemLayoutSizeFitting(
      CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .fittingSizeLevel,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    return max(64, ceil(height))
  }
}
