import UIKit

final class ChatFileCell: UICollectionViewListCell, ChatGapCell {
  var gapAbove: CGFloat = 0 {
    didSet { if gapAbove != oldValue { setNeedsLayout() } }
  }
  static let headerHeight: CGFloat = 42

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
    let content = bounds.inset(by: UIEdgeInsets(top: gapAbove, left: 0, bottom: 0, right: 0))
    for view in subviews where view !== chrome && view !== backgroundView && view !== selectedBackgroundView {
      if view === contentView {
        view.frame = CGRect(x: view.frame.minX, y: content.minY, width: view.frame.width, height: content.height)
      } else {
        view.center.y = content.midY
      }
    }
    chrome.frame = content
    separator.frame = CGRect(
      x: 14,
      y: chrome.bounds.height - 0.5,
      width: max(0, chrome.bounds.width - 28),
      height: 0.5
    )
  }

  static func title(for path: String) -> NSAttributedString {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let name = (normalized as NSString).lastPathComponent
    let directory = String(normalized.dropLast(name.count))
    let title = NSMutableAttributedString(string: name, attributes: [
      .font: LodyDesign.mono(13),
      .foregroundColor: UIColor.lodyInk,
    ])
    guard !directory.isEmpty else { return title }
    title.append(NSAttributedString(string: "  " + directory, attributes: [
      .font: LodyDesign.font(.footnote, size: 12.5),
      .foregroundColor: UIColor.lodyTertiary,
    ]))
    return title
  }

  static func stat(add: Int, del: Int) -> NSAttributedString {
    let parts = [
      add > 0 ? NSAttributedString(string: "+\(add)", attributes: [.foregroundColor: UIColor.systemGreen]) : nil,
      del > 0 ? NSAttributedString(string: "−\(del)", attributes: [.foregroundColor: UIColor.systemRed]) : nil,
    ].compactMap { $0 }
    let result = NSMutableAttributedString()
    for (index, part) in parts.enumerated() {
      if index > 0 { result.append(NSAttributedString(string: " ")) }
      result.append(part)
    }
    return result
  }

  static func counts(add: Int, del: Int, size: CGFloat) -> UILabel {
    let label = UILabel()
    label.font = LodyDesign.font(.footnote, size: size).withTabularNumbers()
    label.attributedText = stat(add: add, del: del)
    label.sizeToFit()
    return label
  }

  static func headerAccessories(add: Int, del: Int, open: Bool) -> [UICellAccessory] {
    let fold = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
    fold.tintColor = .lodySecondary
    fold.transform = open ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
    return [
      .customView(configuration: .init(customView: counts(add: add, del: del, size: 13), placement: .trailing(), reservedLayoutWidth: .actual)),
      .customView(configuration: .init(customView: fold, placement: .trailing())),
    ]
  }

  static func rowAccessories(add: Int, del: Int) -> [UICellAccessory] {
    [.customView(configuration: .init(customView: counts(add: add, del: del, size: 12), placement: .trailing()))]
  }

  static func reviewAccessories() -> [UICellAccessory] {
    []
  }

  static func headerContent(for text: String) -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    content.text = text
    content.textProperties.font = LodyDesign.font(.subheadline, size: 14, weight: .medium)
    content.textProperties.color = .lodyInk
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingTail
    return content
  }

  static func rowContent(for path: String = "Filename") -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    content.attributedText = title(for: path)
    content.textProperties.font = LodyDesign.mono(13)
    content.textProperties.color = .lodyInk
    content.textProperties.numberOfLines = 1
    content.textProperties.lineBreakMode = .byTruncatingTail
    return content
  }

  static func rowHeight() -> CGFloat {
    40
  }
}

enum ChatFileBlock {
  static func visible(_ rows: [ChatRow], expanded: Set<String>, reviewable: Bool) -> [ChatRow] {
    var result: [ChatRow] = []
    for row in rows {
      let open = expanded.contains(row.entryID)
      if row.kind == "changesHeader" {
        var header = row
        header.group = open ? "first" : "only"
        result.append(header)
        continue
      }
      guard row.kind == "changes", row.group != "only" else {
        result.append(row)
        continue
      }
      guard open else { continue }
      var file = row
      if row.group == "last" && reviewable { file.group = "middle" }
      result.append(file)
      if row.group == "last" && reviewable {
        var review = ChatRow(
          id: row.entryID + ":changesReview", entryID: row.entryID, kind: "changesReview",
          text: String(localized: "native.chat.changes.reviewAll", bundle: .lody), actionable: true
        )
        review.group = "last"
        result.append(review)
      }
    }
    return result
  }
}
