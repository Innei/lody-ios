import UIKit

struct LodySessionRowContent: UIContentConfiguration {
  var row: LodyListRow
  var dot: UIColor?
  var live: Bool

  func makeContentView() -> UIView & UIContentView { LodySessionRowView(self) }
  func updated(for state: UIConfigurationState) -> LodySessionRowContent { self }
}

private final class PillLabel: UILabel {
  let insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
  override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
  override var intrinsicContentSize: CGSize {
    guard let text, !text.isEmpty else { return .zero }
    let size = super.intrinsicContentSize
    return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
  }
}

final class LodySessionRowView: UIView, UIContentView {
  private let title = UILabel()
  private let subtitle = UILabel()
  private let time = UILabel()
  private let pill = PillLabel()

  var configuration: UIContentConfiguration {
    didSet { apply() }
  }

  init(_ configuration: LodySessionRowContent) {
    self.configuration = configuration
    super.init(frame: .zero)
    insetsLayoutMarginsFromSafeArea = false
    preservesSuperviewLayoutMargins = false
    directionalLayoutMargins = .init(top: 13, leading: 4, bottom: 13, trailing: 0)
    title.font = .preferredFont(forTextStyle: .body)
    title.numberOfLines = 2
    title.adjustsFontForContentSizeCategory = true
    subtitle.adjustsFontForContentSizeCategory = true
    subtitle.font = .preferredFont(forTextStyle: .footnote)
    time.font = .preferredFont(forTextStyle: .footnote)
    time.adjustsFontForContentSizeCategory = true
    time.textColor = .secondaryLabel
    time.textAlignment = .right
    pill.font = .preferredFont(forTextStyle: .caption1).withWeight(.medium)
    pill.adjustsFontForContentSizeCategory = true
    pill.layer.cornerRadius = 10
    pill.layer.cornerCurve = .continuous
    pill.clipsToBounds = true
    for label in [title, subtitle, time] {
      label.lineBreakMode = .byTruncatingTail
    }
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    time.setContentCompressionResistancePriority(.required, for: .horizontal)
    pill.setContentCompressionResistancePriority(.required, for: .horizontal)
    for view in [title, subtitle, time, pill] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    addSubview(title)
    addSubview(subtitle)
    addSubview(time)
    addSubview(pill)
    let margin = layoutMarginsGuide
    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: margin.topAnchor),
      title.leadingAnchor.constraint(equalTo: margin.leadingAnchor, constant: 16),
      title.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -10),
      subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
      subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      subtitle.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -8),
      subtitle.bottomAnchor.constraint(equalTo: margin.bottomAnchor),
      time.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
      time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
      pill.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 4),
      pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
      pill.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor),
    ])
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  private func apply() {
    guard let content = configuration as? LodySessionRowContent else { return }
    let row = content.row
    let tint = content.dot ?? .secondaryLabel
    title.attributedText = Self.title(for: row, live: content.live, tint: tint)
    subtitle.attributedText = Self.subtitle(for: row)
    subtitle.isHidden = subtitle.attributedText?.length == 0
    time.text = row.value
    pill.text = row.badge
    pill.isHidden = row.badge.isEmpty
    pill.textColor = tint
    pill.backgroundColor = tint.withAlphaComponent(0.16)
    isAccessibilityElement = true
    accessibilityLabel = [row.title, row.badge, subtitle.attributedText?.string ?? "", row.value]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  private static func title(for row: LodyListRow, live: Bool, tint: UIColor) -> NSAttributedString {
    let font = UIFont.preferredFont(forTextStyle: row.unread ? .headline : .body)
    let color: UIColor = row.destructive ? .systemRed : .label
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let text = NSMutableAttributedString()
    if live {
      let mark: CGFloat = 8
      let image = UIGraphicsImageRenderer(size: CGSize(width: mark, height: mark)).image { _ in
        tint.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: mark, height: mark))).fill()
      }
      let attachment = NSTextAttachment()
      attachment.image = image
      attachment.bounds = CGRect(x: 0, y: (font.capHeight - mark) / 2, width: mark, height: mark)
      text.append(NSAttributedString(attachment: attachment))
      text.append(NSAttributedString(string: "\u{00A0}", attributes: attributes))
    }
    text.append(NSAttributedString(string: row.title, attributes: attributes))
    return text
  }

  private static func subtitle(for row: LodyListRow) -> NSAttributedString {
    let footnote = UIFont.preferredFont(forTextStyle: .footnote)
    let base: UIFont = row.subtitleMono
      ? .monospacedSystemFont(ofSize: footnote.pointSize, weight: .regular)
      : footnote
    let text = NSMutableAttributedString()
    if !row.subtitle.isEmpty {
      text.append(NSAttributedString(string: row.subtitle, attributes: [.font: base, .foregroundColor: UIColor.secondaryLabel]))
    }
    let add = row.diff["add"] ?? 0, del = row.diff["del"] ?? 0
    if add > 0 || del > 0 {
      let mono = UIFont.monospacedDigitSystemFont(ofSize: footnote.pointSize, weight: .regular)
      if text.length > 0 {
        text.append(NSAttributedString(string: " · ", attributes: [.font: footnote, .foregroundColor: UIColor.tertiaryLabel]))
      }
      text.append(NSAttributedString(string: "+\(add)", attributes: [.font: mono, .foregroundColor: UIColor.systemBlue]))
      text.append(NSAttributedString(string: " −\(del)", attributes: [.font: mono, .foregroundColor: UIColor.systemRed]))
    }
    return text
  }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let traits = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: traits, size: pointSize)
  }
}
