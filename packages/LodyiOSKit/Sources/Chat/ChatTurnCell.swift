import UIKit

final class ChatTurnCell: UICollectionViewCell {
  static let height: CGFloat = 52
  private static let gap: CGFloat = 8

  private let label = UILabel()
  private let leadingRule = UIView()
  private let trailingRule = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    label.textColor = .lodyTertiary
    label.textAlignment = .center
    label.adjustsFontForContentSizeCategory = true
    for rule in [leadingRule, trailingRule] {
      rule.backgroundColor = .lodyLine2
      contentView.addSubview(rule)
    }
    contentView.addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func configure(_ row: ChatRow) {
    label.font = LodyDesign.mono(11, compatibleWith: traitCollection)
    label.text = row.text
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let bounds = contentView.bounds
    let size = label.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
    let width = ceil(size.width)
    label.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - ceil(size.height)) / 2, width: width, height: ceil(size.height))
    let y = label.frame.midY - 0.25
    leadingRule.frame = CGRect(x: 0, y: y, width: max(0, label.frame.minX - Self.gap), height: 0.5)
    trailingRule.frame = CGRect(x: label.frame.maxX + Self.gap, y: y, width: max(0, bounds.width - label.frame.maxX - Self.gap), height: 0.5)
  }
}
