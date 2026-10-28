import UIKit

final class ChatFileCell: UICollectionViewListCell {
  static let iconSize: CGFloat = 18
  static let iconGap: CGFloat = 8
  static let minHeight: CGFloat = 44

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
    let inset = directionalLayoutMargins.leading + Self.iconSize + Self.iconGap
    separator.frame = CGRect(
      x: inset,
      y: bounds.height - 1 / scale,
      width: max(0, bounds.width - inset - 16),
      height: 1 / scale
    )
  }

  static func title(for path: String) -> NSAttributedString {
    let normalized = path.replacingOccurrences(of: "\\", with: "/") as NSString
    let name = normalized.lastPathComponent
    let parent = (normalized.deletingLastPathComponent as NSString).lastPathComponent
    let font = UIFont.preferredFont(forTextStyle: .subheadline)
    let text = NSMutableAttributedString(string: name, attributes: [
      .font: font,
      .foregroundColor: UIColor.label,
    ])
    if !parent.isEmpty && parent != "." && parent != "/" {
      text.append(NSAttributedString(string: " · \(parent)", attributes: [
        .font: UIFont.preferredFont(forTextStyle: .caption1),
        .foregroundColor: UIColor.secondaryLabel,
      ]))
    }
    return text
  }

  static func rowContent(for path: String = "Filename") -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    content.attributedText = title(for: path)
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingTail
    content.image = MaterialFileIcon.image(for: path)
    content.imageProperties.reservedLayoutSize = CGSize(width: iconSize, height: iconSize)
    content.imageProperties.maximumSize = CGSize(width: iconSize, height: iconSize)
    content.imageToTextPadding = iconGap
    return content
  }

  static func rowHeight() -> CGFloat {
    let content = rowContent()
    let text = ceil(UIFont.preferredFont(forTextStyle: .subheadline).lineHeight)
    let vertical = content.directionalLayoutMargins.top + content.directionalLayoutMargins.bottom
    return max(minHeight, max(iconSize, text) + vertical)
  }
}
