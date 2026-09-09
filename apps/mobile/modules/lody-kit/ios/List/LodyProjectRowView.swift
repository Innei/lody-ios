import UIKit

struct LodyProjectRowContent: UIContentConfiguration {
  var row: LodyListRow
  var accent: UIColor

  func makeContentView() -> UIView & UIContentView { LodyProjectRowView(self) }
  func updated(for state: UIConfigurationState) -> LodyProjectRowContent { self }
}

final class LodyProjectRowView: UIView, UIContentView {
  private let tile = UILabel()
  private let name = UILabel()
  private let path = UILabel()
  private let dot = UIView()
  private let count = UILabel()
  private let chip = PillLabel()
  private let text = UIStackView()

  var configuration: UIContentConfiguration {
    didSet { apply() }
  }

  init(_ configuration: LodyProjectRowContent) {
    self.configuration = configuration
    super.init(frame: .zero)
    insetsLayoutMarginsFromSafeArea = false
    preservesSuperviewLayoutMargins = false
    directionalLayoutMargins = .init(top: 11, leading: 16, bottom: 11, trailing: 4)
    tile.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
    tile.textAlignment = .center
    tile.layer.cornerRadius = 9
    tile.layer.cornerCurve = .continuous
    tile.clipsToBounds = true
    name.font = .preferredFont(forTextStyle: .headline)
    name.adjustsFontForContentSizeCategory = true
    name.lineBreakMode = .byTruncatingTail
    path.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
    path.textColor = .secondaryLabel
    path.lineBreakMode = .byTruncatingMiddle
    count.font = .preferredFont(forTextStyle: .footnote)
    count.adjustsFontForContentSizeCategory = true
    count.textColor = .secondaryLabel
    count.textAlignment = .right
    count.setContentHuggingPriority(.required, for: .horizontal)
    count.setContentCompressionResistancePriority(.required, for: .horizontal)
    chip.setContentHuggingPriority(.required, for: .horizontal)
    chip.setContentCompressionResistancePriority(.required, for: .horizontal)
    chip.font = .preferredFont(forTextStyle: .caption1).withWeight(.medium)
    chip.adjustsFontForContentSizeCategory = true
    chip.layer.cornerRadius = 10
    chip.layer.cornerCurve = .continuous
    chip.clipsToBounds = true
    chip.textColor = .label
    chip.backgroundColor = .tertiarySystemFill
    dot.layer.cornerRadius = 4
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    text.axis = .vertical
    text.spacing = 2
    text.addArrangedSubview(name)
    text.addArrangedSubview(path)
    for view in [tile, text, dot, count, chip] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    let margin = layoutMarginsGuide
    // The >= margins bound the height; this pulls it down to the taller of tile and text.
    let shrink = heightAnchor.constraint(equalToConstant: 0)
    shrink.priority = .defaultLow
    // The stack has no intrinsic width of its own; fill up to the trailing group.
    let fill = text.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -10)
    fill.priority = .defaultHigh
    NSLayoutConstraint.activate([
      tile.widthAnchor.constraint(equalToConstant: 32),
      tile.heightAnchor.constraint(equalToConstant: 32),
      tile.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      tile.centerYAnchor.constraint(equalTo: centerYAnchor),
      tile.topAnchor.constraint(greaterThanOrEqualTo: margin.topAnchor),
      text.topAnchor.constraint(greaterThanOrEqualTo: margin.topAnchor),
      text.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor),
      text.centerYAnchor.constraint(equalTo: centerYAnchor),
      text.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
      text.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -10),
      text.trailingAnchor.constraint(lessThanOrEqualTo: chip.leadingAnchor, constant: -10),
      shrink,
      fill,
      count.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
      count.centerYAnchor.constraint(equalTo: centerYAnchor),
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
      dot.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -6),
      dot.centerYAnchor.constraint(equalTo: count.centerYAnchor),
      chip.trailingAnchor.constraint(equalTo: margin.trailingAnchor),
      chip.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  private func apply() {
    guard let content = configuration as? LodyProjectRowContent else { return }
    let row = content.row
    tile.text = row.monogram
    tile.textColor = content.accent
    tile.backgroundColor = content.accent.withAlphaComponent(0.14)
    name.text = row.title
    path.text = row.subtitle
    path.isHidden = row.subtitle.isEmpty
    count.text = row.value
    count.isHidden = row.value.isEmpty
    let tint = lodyTint(row.imageTint)
    dot.backgroundColor = tint
    dot.isHidden = tint == nil || row.value.isEmpty
    chip.text = row.badge
    chip.isHidden = row.badge.isEmpty
    isAccessibilityElement = true
    accessibilityLabel = [row.title, row.subtitle, row.value, row.badge]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }
}
