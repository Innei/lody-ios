import UIKit

final class ChatSubagentCell: UICollectionViewCell {
  private let card = UIView()
  private let badge = UIView()
  private let icon = UIImageView()
  private let actorLabel = UILabel()
  private let backgroundTag = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let statusIcon = UIImageView()
  private let statusLabel = UILabel()
  private let chevron = UIImageView()
  private let descriptionLabel = UILabel()
  private let detailLabel = UILabel()
  private let groupLabel = UILabel()
  private let separator = UIView()
  private var row: ChatRow?

  private static let inset: CGFloat = 4
  private static let padding = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
  private static let badgeSize: CGFloat = 26
  private static let textLeading = padding.left + badgeSize + 8

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(card)
    card.layer.cornerRadius = 14
    card.layer.cornerCurve = .continuous
    card.backgroundColor = .secondarySystemBackground
    badge.backgroundColor = .systemBackground
    badge.layer.cornerRadius = Self.badgeSize / 2
    icon.contentMode = .center
    badge.addSubview(icon)
    backgroundTag.textColor = .secondaryLabel
    backgroundTag.backgroundColor = .tertiarySystemFill
    backgroundTag.textAlignment = .center
    backgroundTag.layer.cornerRadius = 6
    backgroundTag.layer.cornerCurve = .continuous
    backgroundTag.clipsToBounds = true
    backgroundTag.text = LodyStrings.text("native.chat.subagent.background")
    spinner.hidesWhenStopped = true
    spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
    statusIcon.contentMode = .center
    chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    chevron.tintColor = .tertiaryLabel
    chevron.contentMode = .center
    descriptionLabel.textColor = .label
    descriptionLabel.numberOfLines = 2
    detailLabel.numberOfLines = 2
    groupLabel.textColor = .secondaryLabel
    separator.backgroundColor = .separator
    [badge, actorLabel, backgroundTag, spinner, statusIcon, statusLabel, chevron, descriptionLabel, detailLabel,
     groupLabel, separator].forEach(card.addSubview)
    card.subviews.forEach { $0.isAccessibilityElement = false }
    isAccessibilityElement = true
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: ChatSubagentCell, _) in
      if let row = cell.row { cell.configure(row) }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isHighlighted: Bool {
    didSet { card.alpha = isHighlighted ? 0.6 : 1 }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    spinner.stopAnimating()
  }

  func configure(_ row: ChatRow) {
    self.row = row
    guard let card = row.subagent else { return }
    let failed = card.status == "failed"
    let symbols = ["failed": "exclamationmark.triangle.fill", "cancelled": "minus.circle.fill",
      "unknown": "questionmark.circle.fill"]
    icon.image = UIImage(
      systemName: symbols[card.status] ?? "person.2.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    )
    let tints: [String: UIColor] = ["failed": .systemRed, "cancelled": .secondaryLabel, "unknown": .secondaryLabel]
    icon.tintColor = tints[card.status] ?? .systemBlue
    groupLabel.text = card.groupTitle
    groupLabel.font = Self.statusFont(traitCollection)
    groupLabel.isHidden = card.groupTitle.isEmpty
    separator.isHidden = card.position != "middle" && card.position != "last"
    let corners: [String: CACornerMask] = [
      "first": [.layerMinXMinYCorner, .layerMaxXMinYCorner],
      "middle": [],
      "last": [.layerMinXMaxYCorner, .layerMaxXMaxYCorner],
    ]
    self.card.layer.maskedCorners = corners[card.position]
      ?? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    actorLabel.text = card.actor
    actorLabel.font = Self.actorFont(traitCollection)
    backgroundTag.isHidden = !card.background
    backgroundTag.font = Self.tagFont(traitCollection)
    statusLabel.text = Self.statusText(card.status)
    statusLabel.font = Self.statusFont(traitCollection)
    statusLabel.textColor = failed ? .systemRed : .secondaryLabel
    if card.status == "in_progress" || card.status == "pending" {
      spinner.startAnimating()
    } else {
      spinner.stopAnimating()
    }
    statusIcon.isHidden = card.status != "completed"
    statusIcon.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
    statusIcon.tintColor = .secondaryLabel
    descriptionLabel.text = card.description
    descriptionLabel.font = Self.descriptionFont(traitCollection)
    descriptionLabel.isHidden = card.description.isEmpty
    detailLabel.text = card.detail
    detailLabel.font = Self.detailFont(card, traits: traitCollection)
    detailLabel.textColor = Self.detailColor(card)
    detailLabel.numberOfLines = card.status == "in_progress" ? 1 : 2
    detailLabel.isHidden = card.detail.isEmpty
    accessibilityIdentifier = row.id
    accessibilityLabel = [card.actor, card.description].filter { !$0.isEmpty }.joined(separator: ", ")
    accessibilityValue = [card.groupTitle, statusLabel.text ?? "", card.detail].filter { !$0.isEmpty }.joined(separator: ", ")
    accessibilityTraits = row.actionable ? .button : .staticText
    setNeedsLayout()
  }

  private static func statusText(_ status: String) -> String {
    let keys = [
      "pending": "native.chat.subagent.pending",
      "in_progress": "native.chat.subagent.running",
      "completed": "native.chat.subagent.completed",
      "failed": "native.chat.subagent.failed",
      "cancelled": "native.chat.subagent.cancelled",
      "unknown": "native.chat.subagent.unknown",
    ]
    return keys[status].map { LodyStrings.text($0) } ?? ""
  }

  private static func actorFont(_ traits: UITraitCollection) -> UIFont {
    UIFont.systemFont(ofSize: UIFont.dynamic(of: 15, compatibleWith: traits).pointSize, weight: .semibold)
  }
  private static func tagFont(_ traits: UITraitCollection) -> UIFont {
    UIFont.systemFont(ofSize: UIFont.dynamic(of: 11, compatibleWith: traits).pointSize, weight: .medium)
  }
  private static func statusFont(_ traits: UITraitCollection) -> UIFont {
    UIFont.dynamic(of: 13, compatibleWith: traits)
  }
  private static func descriptionFont(_ traits: UITraitCollection) -> UIFont {
    UIFont.dynamic(of: 15, compatibleWith: traits)
  }
  private static func detailFont(_ card: ChatSubagentCard, traits: UITraitCollection) -> UIFont {
    UIFont.dynamic(of: card.status == "in_progress" ? 13 : 14, compatibleWith: traits)
  }
  private static func detailColor(_ card: ChatSubagentCard) -> UIColor {
    card.status == "failed" ? .systemRed : .secondaryLabel
  }

  private static func textHeight(_ text: String, width: CGFloat, font: UIFont, lines: Int) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let bounds = (text as NSString).boundingRect(
      with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
    )
    return ceil(min(bounds.height, font.lineHeight * CGFloat(lines)))
  }

  private static func headerHeight(_ traits: UITraitCollection) -> CGFloat {
    max(badgeSize, ceil(actorFont(traits).lineHeight))
  }

  private static func bodyHeights(_ card: ChatSubagentCard, width: CGFloat, traits: UITraitCollection) -> (CGFloat, CGFloat) {
    let textWidth = width - textLeading - padding.right
    let description = textHeight(card.description, width: textWidth, font: descriptionFont(traits), lines: 2)
    let detail = textHeight(card.detail, width: textWidth, font: detailFont(card, traits: traits),
      lines: card.status == "in_progress" ? 1 : 2)
    return (description, detail)
  }

  private static func insets(_ card: ChatSubagentCard) -> (top: CGFloat, bottom: CGFloat) {
    (["only", "first"].contains(card.position) ? inset : 0, ["only", "last"].contains(card.position) ? inset : 0)
  }

  private static func groupHeight(_ card: ChatSubagentCard, traits: UITraitCollection) -> CGFloat {
    card.groupTitle.isEmpty ? 0 : ceil(statusFont(traits).lineHeight) + 8
  }

  static func height(_ row: ChatRow, width: CGFloat, traits: UITraitCollection) -> CGFloat {
    guard let card = row.subagent else { return 0 }
    let (description, detail) = bodyHeights(card, width: width, traits: traits)
    let (top, bottom) = insets(card)
    return top + bottom + groupHeight(card, traits: traits) + padding.top + headerHeight(traits)
      + (description > 0 ? 2 + description : 0)
      + (detail > 0 ? 3 + detail : 0) + padding.bottom
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let row, let data = row.subagent else { return }
    let (top, bottom) = Self.insets(data)
    card.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top - bottom)
    let width = card.bounds.width
    let group = Self.groupHeight(data, traits: traitCollection)
    groupLabel.frame = CGRect(x: Self.padding.left, y: 10, width: width - Self.padding.left * 2, height: max(0, group - 8))
    separator.frame = CGRect(x: Self.textLeading, y: 0, width: width - Self.textLeading, height: 1 / max(1, traitCollection.displayScale))
    var pad = Self.padding
    pad.top += group
    let header = Self.headerHeight(traitCollection)
    let midY = pad.top + header / 2
    badge.frame = CGRect(x: pad.left, y: midY - Self.badgeSize / 2, width: Self.badgeSize, height: Self.badgeSize)
    icon.frame = badge.bounds
    chevron.frame = CGRect(x: width - pad.right - 12, y: midY - 8, width: 12, height: 16)
    var trailing = chevron.frame.minX - 8
    let statusSize = statusLabel.sizeThatFits(CGSize(width: width / 3, height: header))
    statusLabel.frame = CGRect(x: trailing - statusSize.width, y: midY - statusSize.height / 2,
      width: statusSize.width, height: statusSize.height)
    trailing = statusLabel.frame.minX - 4
    if spinner.isAnimating {
      spinner.center = CGPoint(x: trailing - 7, y: midY)
      trailing -= 18
    } else if !statusIcon.isHidden {
      statusIcon.frame = CGRect(x: trailing - 14, y: midY - 7, width: 14, height: 14)
      trailing -= 18
    }
    var tagWidth: CGFloat = 0
    if !backgroundTag.isHidden {
      let size = backgroundTag.sizeThatFits(CGSize(width: width, height: header))
      tagWidth = ceil(size.width) + 12
    }
    let actorMax = max(1, trailing - 8 - Self.textLeading - (tagWidth > 0 ? tagWidth + 6 : 0))
    let actorWidth = min(actorMax, ceil(actorLabel.sizeThatFits(CGSize(width: width, height: header)).width))
    actorLabel.frame = CGRect(x: Self.textLeading, y: pad.top, width: actorWidth, height: header)
    if tagWidth > 0 {
      let tagHeight = ceil(backgroundTag.font.lineHeight) + 4
      backgroundTag.frame = CGRect(x: actorLabel.frame.maxX + 6, y: midY - tagHeight / 2, width: tagWidth, height: tagHeight)
    }
    let (description, detail) = Self.bodyHeights(data, width: width, traits: traitCollection)
    let textWidth = max(1, width - Self.textLeading - pad.right)
    var y = pad.top + header
    if description > 0 {
      y += 2
      descriptionLabel.frame = CGRect(x: Self.textLeading, y: y, width: textWidth, height: description)
      y += description
    }
    if detail > 0 {
      y += 3
      detailLabel.frame = CGRect(x: Self.textLeading, y: y, width: textWidth, height: detail)
    }
  }
}
