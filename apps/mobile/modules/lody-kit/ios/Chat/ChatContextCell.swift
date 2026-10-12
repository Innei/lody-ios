import UIKit

/// Read-only session state keeps its own rail outside the agent's execution process.
final class ChatContextCell: UICollectionViewCell {
  private let surface = UIView()
  private let icon = UIImageView()
  private let title = UILabel()
  private let detail = UILabel()
  private var row: ChatRow?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(surface)
    surface.addSubview(icon)
    surface.addSubview(title)
    surface.addSubview(detail)
    surface.layer.cornerRadius = 12
    title.numberOfLines = 0
    detail.numberOfLines = 0
    title.adjustsFontForContentSizeCategory = true
    detail.adjustsFontForContentSizeCategory = true
    icon.contentMode = .top
    isAccessibilityElement = true
    accessibilityTraits = .staticText
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) {
      (cell: ChatContextCell, _) in cell.apply()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ row: ChatRow) {
    self.row = row
    accessibilityIdentifier = row.id
    accessibilityLabel = [row.text, row.contextDetail].filter { !$0.isEmpty }.joined(separator: ", ")
    apply()
    setNeedsLayout()
  }

  private func apply() {
    guard let row else { return }
    surface.backgroundColor = .secondarySystemGroupedBackground
    title.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
    title.textColor = .label
    title.text = row.text
    detail.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    detail.textColor = .secondaryLabel
    detail.text = row.contextDetail
    detail.isHidden = row.contextDetail.isEmpty
    icon.tintColor = .secondaryLabel
    icon.image = UIImage(systemName: row.symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    surface.frame = bounds.insetBy(dx: 0, dy: 4)
    let width = max(1, surface.bounds.width - 52)
    let titleHeight = title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    icon.frame = CGRect(x: 12, y: 12, width: 20, height: 20)
    title.frame = CGRect(x: 40, y: 12, width: width, height: ceil(titleHeight))
    detail.frame = CGRect(x: 40, y: title.frame.maxY + 4, width: width, height: max(0, surface.bounds.height - title.frame.maxY - 16))
  }

  static func height(_ row: ChatRow, width: CGFloat, traits: UITraitCollection) -> CGFloat {
    let bodyWidth = max(1, width - 52)
    func measure(_ text: String, style: UIFont.TextStyle) -> CGFloat {
      (text as NSString).boundingRect(with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)], context: nil).height
    }
    let title = measure(row.text, style: .subheadline)
    let detail = row.contextDetail.isEmpty ? 0 : measure(row.contextDetail, style: .footnote) + 4
    return max(52, ceil(title + detail) + 32)
  }
}
