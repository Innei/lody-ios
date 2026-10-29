import UIKit

struct LodyProjectRowContent: UIContentConfiguration {
  var row: LodyListRow
  var density: LodyRowDensity = .regular
  var expanded: Bool?
  var onToggle: (@MainActor () -> Void)?

  var accessibilityLabel: String {
    [row.title, row.subtitle, row.value, row.badge].filter { !$0.isEmpty }.joined(separator: ", ")
  }

  func makeContentView() -> UIView & UIContentView { LodyProjectRowView(self) }
  func updated(for state: UIConfigurationState) -> LodyProjectRowContent {
    guard expanded != nil, let cell = state as? UICellConfigurationState else { return self }
    var copy = self
    copy.expanded = cell.isExpanded
    return copy
  }
}

final class LodyProjectRowView: UIView, UIContentView {
  private let glyph = LodyStatusGlyphView(kind: .project)
  private let symbol = UIImageView()
  private let name = UILabel()
  private let detail = UILabel()
  private let count = UILabel()
  private let fold = UIImageView()
  private var glyphCenter: NSLayoutConstraint!
  private var withDetail: [NSLayoutConstraint] = []
  private var withoutDetail: [NSLayoutConstraint] = []
  private var withFold: [NSLayoutConstraint] = []

  var configuration: UIContentConfiguration {
    didSet { apply() }
  }

  init(_ configuration: LodyProjectRowContent) {
    self.configuration = configuration
    super.init(frame: .zero)
    insetsLayoutMarginsFromSafeArea = false
    preservesSuperviewLayoutMargins = false
    symbol.tintColor = .lodySecondary
    symbol.contentMode = .center
    fold.tintColor = .lodyTertiary
    fold.contentMode = .center
    fold.setContentCompressionResistancePriority(.required, for: .horizontal)
    name.adjustsFontForContentSizeCategory = true
    name.textColor = .lodyInk
    detail.adjustsFontForContentSizeCategory = true
    count.adjustsFontForContentSizeCategory = true
    count.textColor = .lodyTertiary
    count.textAlignment = .right
    for label in [name, detail, count] {
      label.lineBreakMode = .byTruncatingTail
    }
    detail.lineBreakMode = .byTruncatingMiddle
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    count.setContentCompressionResistancePriority(.required, for: .horizontal)
    count.setContentHuggingPriority(.required, for: .horizontal)
    for view in [glyph, symbol, name, detail, count, fold] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    let margin = layoutMarginsGuide
    glyphCenter = glyph.centerXAnchor.constraint(equalTo: leadingAnchor)
    let centered = name.centerYAnchor.constraint(equalTo: centerYAnchor)
    centered.priority = .defaultHigh
    let pinned = detail.bottomAnchor.constraint(equalTo: margin.bottomAnchor)
    pinned.priority = .defaultHigh
    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      glyphCenter,
      glyph.widthAnchor.constraint(equalToConstant: LodyDesign.Rail.glyph),
      glyph.heightAnchor.constraint(equalToConstant: LodyDesign.Rail.glyph),
      glyph.centerYAnchor.constraint(equalTo: name.centerYAnchor),
      symbol.centerXAnchor.constraint(equalTo: glyph.centerXAnchor),
      symbol.centerYAnchor.constraint(equalTo: glyph.centerYAnchor),
      name.topAnchor.constraint(equalTo: margin.topAnchor),
      name.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      name.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -10),
      count.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
      count.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
    ])
    withDetail = [
      detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
      detail.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      detail.trailingAnchor.constraint(lessThanOrEqualTo: margin.trailingAnchor),
      detail.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor),
      pinned,
    ]
    withFold = [
      fold.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 5),
      fold.centerYAnchor.constraint(equalTo: name.centerYAnchor),
      fold.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -10),
    ]
    withoutDetail = [
      name.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor),
      centered,
    ]
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  private func apply() {
    guard let content = configuration as? LodyProjectRowContent else { return }
    let row = content.row
    let compact = content.density == .compact
    directionalLayoutMargins = .init(
      top: compact ? 5 : 8,
      leading: compact ? LodyDesign.Rail.compactText : LodyDesign.Rail.text,
      bottom: compact ? 5 : 8,
      trailing: compact ? 10 : LodyDesign.Rail.trailing
    )
    glyphCenter.constant = compact ? LodyDesign.Rail.compactCenter : LodyDesign.Rail.center
    let image = LodyListPhoto.url(row.image) == nil && !row.image.isEmpty ? UIImage(systemName: row.image) : nil
    symbol.image = image
    symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    symbol.isHidden = image == nil
    glyph.isHidden = image != nil
    let nameFont = LodyDesign.font(.subheadline, size: compact ? 14 : 15, weight: .semibold)
    let nameText = NSMutableAttributedString(string: row.title, attributes: [.font: nameFont, .foregroundColor: UIColor.lodyInk])
    LodySessionRowView.emphasize(nameText, in: NSRange(location: 0, length: nameText.length), query: row.highlight)
    name.font = nameFont
    name.attributedText = nameText
    let body = LodyDesign.font(.footnote, size: compact ? 12 : 12.5)
    let line = NSMutableAttributedString()
    if !row.subtitle.isEmpty {
      line.append(NSAttributedString(string: row.subtitle, attributes: [
        .font: body,
        .foregroundColor: UIColor.lodySecondary,
      ]))
    }
    if !row.value.isEmpty {
      if line.length > 0 {
        line.append(NSAttributedString(string: " · ", attributes: [.font: body, .foregroundColor: UIColor.lodyTertiary]))
      }
      line.append(NSAttributedString(string: row.value, attributes: [.font: body, .foregroundColor: UIColor.lodySecondary]))
    }
    detail.attributedText = line
    let hasDetail = line.length > 0
    detail.isHidden = !hasDetail
    NSLayoutConstraint.deactivate(hasDetail ? withoutDetail : withDetail)
    NSLayoutConstraint.activate(hasDetail ? withDetail : withoutDetail)
    count.font = LodyDesign.mono(compact ? 11 : 11.5)
    count.text = row.badge
    count.isHidden = row.badge.isEmpty
    applyFold(content)
    isAccessibilityElement = true
    accessibilityLabel = content.accessibilityLabel
  }

  private func applyFold(_ content: LodyProjectRowContent) {
    guard let expanded = content.expanded else {
      fold.isHidden = true
      NSLayoutConstraint.deactivate(withFold)
      accessibilityValue = nil
      accessibilityCustomActions = nil
      return
    }
    let symbol = expanded ? "chevron.down" : "chevron.right"
    fold.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .heavy))
    fold.isHidden = false
    NSLayoutConstraint.activate(withFold)
    accessibilityValue = String(localized: String.LocalizationValue(expanded ? "native.list.expanded" : "native.list.collapsed"), bundle: .lody)
    let toggle = String(localized: String.LocalizationValue(expanded ? "native.list.collapse" : "native.list.expand"), bundle: .lody)
    accessibilityCustomActions = content.onToggle.map { onToggle in
      [UIAccessibilityCustomAction(name: toggle) { _ in
        onToggle()
        return true
      }]
    }
  }
}
