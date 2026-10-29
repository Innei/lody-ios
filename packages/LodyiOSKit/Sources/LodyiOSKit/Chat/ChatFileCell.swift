import UIKit

final class ChatFileCell: UICollectionViewListCell {
  static let headerHeight: CGFloat = 44

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
    separator.backgroundColor = .lodyLine
    chrome.addSubview(separator)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(group: String, selected: Bool) {
    backgroundConfiguration = .clear()
    chrome.backgroundColor = selected ? .lodyInsetSelected : .lodyInset
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
    separator.frame = CGRect(
      x: 14,
      y: bounds.height - 0.5,
      width: max(0, bounds.width - 28),
      height: 0.5
    )
  }

  static func title(for path: String) -> NSAttributedString {
    NSAttributedString(string: path.replacingOccurrences(of: "\\", with: "/"), attributes: [
      .font: LodyDesign.mono(12.5),
      .foregroundColor: UIColor.lodyInk,
    ])
  }

  static func headerContent(for text: String) -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    content.text = text
    content.textProperties.font = LodyDesign.font(.subheadline, size: 14.5, weight: .semibold)
    content.textProperties.color = .lodyInk
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingTail
    return content
  }

  static func rowContent(for path: String = "Filename") -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    content.attributedText = title(for: path)
    content.textProperties.font = LodyDesign.mono(12.5)
    content.textProperties.color = .lodyInk
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingTail
    return content
  }

  static func rowHeight() -> CGFloat {
    44
  }
}
