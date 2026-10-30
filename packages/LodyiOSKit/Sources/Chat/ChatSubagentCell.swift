import UIKit

final class ChatSubagentCell: UICollectionViewCell, ChatGapCell {
  var gapAbove: CGFloat = 0 {
    didSet { if gapAbove != oldValue { setNeedsLayout() } }
  }
  private let glyph = LodyStatusGlyphView(kind: .done)
  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  private let detailLabel = UILabel()
  private lazy var tree = LodyTentacle(in: contentView.layer)
  private var row: ChatRow?

  override init(frame: CGRect) {
    super.init(frame: frame)
    _ = tree
    for view in [glyph, titleLabel, statusLabel, detailLabel] as [UIView] {
      view.isAccessibilityElement = false
      contentView.addSubview(view)
    }
    for label in [titleLabel, statusLabel, detailLabel] {
      label.numberOfLines = 1
      label.lineBreakMode = .byTruncatingTail
    }
    statusLabel.textAlignment = .right
    detailLabel.textColor = .lodySecondary
    isAccessibilityElement = true
    registerForTraitChanges([
      UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self,
    ]) { (cell: ChatSubagentCell, _) in
      if let row = cell.row { cell.configure(row) }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isHighlighted: Bool {
    didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    row = nil
    glyph.kind = .none
    tree.apply(UIBezierPath(), live: false, frame: contentView.bounds, traits: traitCollection)
    contentView.alpha = 1
  }

  func configure(_ row: ChatRow) {
    self.row = row
    guard let card = row.subagent else { return }
    switch card.status {
    case "pending", "in_progress": glyph.kind = .live
    case "failed": glyph.kind = .failed
    default: glyph.kind = .done
    }
    let font = Self.titleFont(traitCollection)
    let title = NSMutableAttributedString(string: card.description, attributes: [
      .font: font, .foregroundColor: UIColor.lodyInk,
    ])
    if !card.actor.isEmpty {
      let actor = card.description.isEmpty ? card.actor : " · " + card.actor
      let color: UIColor = card.description.isEmpty ? .lodyInk : .lodySecondary
      title.append(NSAttributedString(string: actor, attributes: [.font: font, .foregroundColor: color]))
    }
    titleLabel.attributedText = title
    var status = Self.statusText(card.status)
    if card.status == "in_progress", !card.detail.isEmpty { status = card.detail }
    if card.background {
      status += " · " + String(localized: "native.chat.subagent.background", bundle: .lody)
    }
    statusLabel.text = status
    statusLabel.font = LodyDesign.mono(11.5, compatibleWith: traitCollection)
    statusLabel.textColor = card.status == "failed" ? .lodyFailure : .lodyTertiary
    detailLabel.text = Self.detailText(card)
    detailLabel.font = Self.detailFont(traitCollection)
    detailLabel.isHidden = Self.detailText(card).isEmpty
    accessibilityIdentifier = row.id
    accessibilityLabel = [card.actor, card.description].filter { !$0.isEmpty }.joined(separator: ", ")
    accessibilityValue = [Self.statusText(card.status), card.detail].filter { !$0.isEmpty }.joined(separator: ", ")
    accessibilityTraits = row.actionable ? .button : .staticText
    setNeedsLayout()
  }

  private static func statusText(_ status: String) -> String {
    let keys = [
      "pending": "native.chat.subagent.pending",
      "in_progress": "native.chat.subagent.running",
      "completed": "native.chat.subagent.completed",
      "failed": "native.chat.subagent.failed",
    ]
    return keys[status].map { String(localized: String.LocalizationValue($0), bundle: .lody) } ?? ""
  }

  private static func detailText(_ card: ChatSubagentCard) -> String {
    card.status == "in_progress" ? "" : card.detail
  }

  private static func titleFont(_ traits: UITraitCollection) -> UIFont {
    LodyDesign.font(.subheadline, size: 14, compatibleWith: traits)
  }

  private static func detailFont(_ traits: UITraitCollection) -> UIFont {
    LodyDesign.font(.footnote, size: 12, compatibleWith: traits)
  }

  private static func firstLine(_ traits: UITraitCollection) -> (top: CGFloat, height: CGFloat, row: CGFloat) {
    let height = ceil(titleFont(traits).lineHeight)
    let row = max(30, height + 12)
    return (floor((row - height) / 2), height, row)
  }

  static func height(_ row: ChatRow, width: CGFloat, traits: UITraitCollection) -> CGFloat {
    guard let card = row.subagent else { return 0 }
    let line = firstLine(traits)
    if detailText(card).isEmpty { return line.row }
    return max(40, line.top + line.height + 1 + ceil(detailFont(traits).lineHeight))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutGap()
    guard let row, row.subagent != nil else { return }
    let width = contentView.bounds.width
    let line = Self.firstLine(traitCollection)
    let center = row.treeChild ? LodyDesign.Rail.childCenter : LodyDesign.Rail.center
    let text = row.treeChild ? LodyDesign.Rail.childText : LodyDesign.Rail.text
    let x = text - ChatReadingColumn.cellMargin
    let available = max(0, width - x)
    let statusWidth = min(ceil(statusLabel.sizeThatFits(CGSize(width: width, height: line.height)).width), available * 0.45)
    let statusHeight = ceil(statusLabel.font.lineHeight)
    let midY = line.top + line.height / 2
    statusLabel.frame = CGRect(x: width - statusWidth, y: midY - statusHeight / 2, width: statusWidth, height: statusHeight)
    titleLabel.frame = CGRect(x: x, y: line.top, width: max(0, statusLabel.frame.minX - x - 8), height: line.height)
    detailLabel.frame = CGRect(x: x, y: titleLabel.frame.maxY + 1, width: available, height: ceil(detailLabel.font.lineHeight))
    let side = LodyDesign.Rail.glyph
    glyph.frame = CGRect(x: center - ChatReadingColumn.cellMargin - side / 2, y: midY - side / 2, width: side, height: side)
    var path = UIBezierPath()
    if row.treeChild {
      let trunk = LodyDesign.Rail.center - ChatReadingColumn.cellMargin
      path = LodyTentacle.branch(
        trunk: trunk, to: CGPoint(x: glyph.frame.minX - 1, y: midY), height: contentView.bounds.height, last: row.treeLast
      )
    }
    tree.apply(path, live: row.treeChild && row.parentLive, frame: contentView.bounds, traits: traitCollection)
  }
}
