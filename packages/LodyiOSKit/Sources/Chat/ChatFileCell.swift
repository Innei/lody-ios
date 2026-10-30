import UIKit

final class ChatFileCell: UICollectionViewListCell {
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
    chrome.frame = bounds
    separator.frame = CGRect(
      x: 14,
      y: bounds.height - 0.5,
      width: max(0, bounds.width - 28),
      height: 0.5
    )
  }

  static func title(for path: String) -> NSAttributedString {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let name = (normalized as NSString).lastPathComponent
    let directory = String(normalized.dropLast(name.count))
    let title = NSMutableAttributedString(string: name, attributes: [
      .font: LodyDesign.mono(12.5, weight: .medium),
      .foregroundColor: UIColor.lodyInk,
    ])
    guard !directory.isEmpty else { return title }
    title.append(NSAttributedString(string: "  " + directory, attributes: [
      .font: LodyDesign.font(.footnote, size: 11.5),
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

  static func summaryAccessory(squares: UIView, counts: UILabel) -> UIView {
    let stack = UIStackView(arrangedSubviews: [squares, counts])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    squares.setContentHuggingPriority(.required, for: .horizontal)
    counts.setContentCompressionResistancePriority(.required, for: .horizontal)
    stack.frame.size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    stack.layoutIfNeeded()
    return stack
  }

  static func diffstat(add: Int, del: Int) -> Int {
    let total = add + del
    guard total > 0 else { return 0 }
    return Int((5 * Double(add) / Double(total)).rounded())
  }

  static func headerContent(for text: String) -> UIListContentConfiguration {
    var content = UIListContentConfiguration.cell()
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    content.text = text
    content.textProperties.font = LodyDesign.font(.subheadline, size: 14, weight: .semibold)
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
    40
  }
}

final class ChatDiffstatView: UIView {
  private let squares = (0..<5).map { _ in UIView() }

  init(add: Int, del: Int) {
    super.init(frame: CGRect(x: 0, y: 0, width: 43, height: 7))
    let green = ChatFileCell.diffstat(add: add, del: del)
    for (index, square) in squares.enumerated() {
      square.frame = CGRect(x: CGFloat(index) * 9, y: 0, width: 7, height: 7)
      square.layer.cornerRadius = 2
      square.backgroundColor = index < green ? .systemGreen : .systemRed
      addSubview(square)
    }
    isAccessibilityElement = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var intrinsicContentSize: CGSize { CGSize(width: 43, height: 7) }
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
