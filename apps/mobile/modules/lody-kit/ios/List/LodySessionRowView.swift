import UIKit

struct LodySessionRowContent: UIContentConfiguration {
  var row: LodyListRow
  var dot: UIColor?
  var live: Bool
  var density: LodyRowDensity = .regular

  @MainActor var accessibilityLabel: String {
    [row.title, row.badge, LodySessionRowView.meta(for: row).string, row.modelName, row.value]
      .filter { !$0.isEmpty }.joined(separator: ", ")
  }

  func makeContentView() -> UIView & UIContentView { LodySessionRowView(self) }
  func updated(for state: UIConfigurationState) -> LodySessionRowContent { self }
}

final class PillLabel: UILabel {
  let insets = UIEdgeInsets(top: 1, left: 7, bottom: 1, right: 7)
  override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
  override var intrinsicContentSize: CGSize {
    guard let text, !text.isEmpty else { return .zero }
    let size = super.intrinsicContentSize
    return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
  }
}

final class LodyIndentedCell: UICollectionViewListCell {
  static let textLeading: CGFloat = 32
  static let markCenter: CGFloat = 18

  override init(frame: CGRect) {
    super.init(frame: frame)
    separatorLayoutGuide.leadingAnchor.constraint(
      equalTo: contentView.leadingAnchor, constant: Self.textLeading
    ).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }
}

final class LodySessionRowView: UIView, UIContentView {
  private let ring = UIView()
  private let dot = UIView()
  private let meta = UILabel()
  private let model = UILabel()
  private let pill = PillLabel()
  private let metaRow = UIStackView()
  private let time = UILabel()
  private let title = UILabel()
  private var withMeta: [NSLayoutConstraint] = []
  private var withoutMeta: [NSLayoutConstraint] = []
  private var markCenter: NSLayoutConstraint!
  private var minimumHeight: NSLayoutConstraint!

  var configuration: UIContentConfiguration {
    didSet { apply() }
  }

  init(_ configuration: LodySessionRowContent) {
    self.configuration = configuration
    super.init(frame: .zero)
    insetsLayoutMarginsFromSafeArea = false
    preservesSuperviewLayoutMargins = false
    directionalLayoutMargins = .init(top: 11, leading: 0, bottom: 11, trailing: 16)
    title.font = .preferredFont(forTextStyle: .body)
    title.numberOfLines = 2
    title.adjustsFontForContentSizeCategory = true
    meta.adjustsFontForContentSizeCategory = true
    meta.font = .preferredFont(forTextStyle: .footnote)
    model.font = .preferredFont(forTextStyle: .footnote)
    model.adjustsFontForContentSizeCategory = true
    model.textColor = .secondaryLabel
    time.font = .preferredFont(forTextStyle: .footnote)
    time.adjustsFontForContentSizeCategory = true
    time.textColor = .secondaryLabel
    time.textAlignment = .right
    pill.font = .preferredFont(forTextStyle: .caption1).withWeight(.medium)
    pill.adjustsFontForContentSizeCategory = true
    pill.layer.cornerRadius = 9
    pill.layer.cornerCurve = .continuous
    pill.clipsToBounds = true
    ring.layer.cornerRadius = 7
    dot.layer.cornerRadius = 4
    for label in [title, meta, model, time] {
      label.lineBreakMode = .byTruncatingTail
    }
    meta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    model.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    time.setContentCompressionResistancePriority(.required, for: .horizontal)
    pill.setContentCompressionResistancePriority(.required, for: .horizontal)
    metaRow.axis = .horizontal
    metaRow.alignment = .center
    metaRow.spacing = 0
    metaRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    for item in [meta, model, pill] { metaRow.addArrangedSubview(item) }
    for view in [ring, dot, metaRow, time, title] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    let margin = layoutMarginsGuide
    minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    markCenter = ring.centerXAnchor.constraint(equalTo: leadingAnchor)
    NSLayoutConstraint.activate([
      markCenter,
      ring.widthAnchor.constraint(equalToConstant: 14),
      ring.heightAnchor.constraint(equalToConstant: 14),
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
      dot.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
      dot.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
      metaRow.topAnchor.constraint(equalTo: margin.topAnchor),
      metaRow.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      metaRow.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -10),
      time.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
      title.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      title.bottomAnchor.constraint(equalTo: margin.bottomAnchor),
      ring.centerYAnchor.constraint(equalTo: title.firstBaselineAnchor, constant: -5),
    ])
    withMeta = [
      time.centerYAnchor.constraint(equalTo: metaRow.centerYAnchor),
      title.topAnchor.constraint(equalTo: metaRow.bottomAnchor, constant: 3),
      title.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
    ]
    withoutMeta = [
      time.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
      title.topAnchor.constraint(equalTo: margin.topAnchor),
      title.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -10),
    ]
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  private func apply() {
    guard let content = configuration as? LodySessionRowContent else { return }
    let row = content.row
    let tint = content.dot ?? .secondaryLabel
    let compact = content.density == .compact
    directionalLayoutMargins = compact
      ? .init(top: 5, leading: 22, bottom: 5, trailing: 10)
      : .init(top: 11, leading: LodyIndentedCell.textLeading, bottom: 11, trailing: 16)
    minimumHeight.isActive = compact
    markCenter.constant = compact ? 10 : LodyIndentedCell.markCenter
    title.text = row.title
    if compact {
      title.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(row.unread ? .semibold : .regular)
    } else {
      title.font = .preferredFont(forTextStyle: row.unread ? .headline : .body)
    }
    let metadataFont = UIFont.preferredFont(forTextStyle: compact ? .caption1 : .footnote)
    meta.font = metadataFont
    model.font = metadataFont
    time.font = metadataFont
    title.textColor = row.destructive ? .systemRed : .label
    let metaText = Self.meta(for: row, density: content.density)
    meta.attributedText = metaText
    let hasText = metaText.length > 0
    let hasModel = !row.modelName.isEmpty
    let hasBadge = !row.badge.isEmpty
    let modelPrefix = hasText ? " · " : ""
    model.text = hasModel ? modelPrefix + row.modelName : nil
    let hasMeta = hasText || hasModel || hasBadge
    meta.isHidden = !hasText
    model.isHidden = !hasModel
    pill.isHidden = !hasBadge
    metaRow.isHidden = !hasMeta
    if hasModel {
      metaRow.setCustomSpacing(5, after: model)
    } else {
      metaRow.setCustomSpacing(hasText && hasBadge ? 5 : 0, after: meta)
    }
    NSLayoutConstraint.deactivate(hasMeta ? withoutMeta : withMeta)
    NSLayoutConstraint.activate(hasMeta ? withMeta : withoutMeta)
    time.text = row.value
    pill.text = row.badge
    pill.textColor = tint
    pill.backgroundColor = tint.withAlphaComponent(0.16)
    dot.backgroundColor = tint
    dot.isHidden = content.dot == nil
    ring.backgroundColor = tint.withAlphaComponent(0.14)
    ring.isHidden = !content.live
    isAccessibilityElement = true
    accessibilityLabel = content.accessibilityLabel
  }

  static func meta(for row: LodyListRow, density: LodyRowDensity = .regular) -> NSAttributedString {
    let footnote = UIFont.preferredFont(forTextStyle: density == .compact ? .caption1 : .footnote)
    let base: UIFont = row.subtitleMono
      ? .monospacedSystemFont(ofSize: footnote.pointSize, weight: .regular)
      : footnote
    let text = NSMutableAttributedString()
    if row.pinned, let pin = UIImage(systemName: "pin.fill") {
      let attachment = NSTextAttachment()
      attachment.image = pin.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
      let side = footnote.capHeight
      attachment.bounds = CGRect(x: 0, y: 0, width: side, height: side)
      text.append(NSAttributedString(attachment: attachment))
      text.append(NSAttributedString(string: " ", attributes: [.font: footnote]))
    }
    if !row.subtitle.isEmpty {
      text.append(NSAttributedString(string: row.subtitle, attributes: [.font: base, .foregroundColor: UIColor.secondaryLabel]))
    }
    let add = row.diff["add"] ?? 0, del = row.diff["del"] ?? 0
    if row.badge.isEmpty, add > 0 || del > 0 {
      let mono = UIFont.monospacedDigitSystemFont(ofSize: footnote.pointSize, weight: .regular)
      if !row.subtitle.isEmpty {
        text.append(NSAttributedString(string: " · ", attributes: [.font: footnote, .foregroundColor: UIColor.tertiaryLabel]))
      }
      text.append(NSAttributedString(string: "+\(add)", attributes: [.font: mono, .foregroundColor: UIColor.systemBlue]))
      text.append(NSAttributedString(string: " −\(del)", attributes: [.font: mono, .foregroundColor: UIColor.systemRed]))
    }
    return text
  }
}

extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let traits = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: traits, size: pointSize)
  }
}
