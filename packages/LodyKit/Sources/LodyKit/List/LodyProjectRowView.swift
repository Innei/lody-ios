import UIKit

struct LodyProjectRowContent: UIContentConfiguration {
  var row: LodyListRow
  var accent: UIColor
  var density: LodyRowDensity = .regular

  var accessibilityLabel: String {
    [row.title, row.subtitle, row.value, row.badge].filter { !$0.isEmpty }.joined(separator: ", ")
  }

  func makeContentView() -> UIView & UIContentView { LodyProjectRowView(self) }
  func updated(for state: UIConfigurationState) -> LodyProjectRowContent { self }
}

final class LodyProjectRowView: UIView, UIContentView {
  private let tile = UILabel()
  private let icon = UIImageView()
  private var photoURL: URL?
  private let name = UILabel()
  private let path = UILabel()
  private let dot = UIView()
  private let count = UILabel()
  private let chip = PillLabel()
  private let text = UIStackView()
  private var textSpacing: NSLayoutConstraint!
  private var tileWidth: NSLayoutConstraint!

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
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: tile.font)
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
    for view in [tile, icon, text, dot, count, chip] {
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
    textSpacing = text.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12)
    tileWidth = tile.widthAnchor.constraint(equalToConstant: 32)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      tileWidth,
      tile.heightAnchor.constraint(equalTo: tile.widthAnchor),
      tile.leadingAnchor.constraint(equalTo: margin.leadingAnchor),
      tile.centerYAnchor.constraint(equalTo: centerYAnchor),
      tile.topAnchor.constraint(greaterThanOrEqualTo: margin.topAnchor),
      icon.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
      icon.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
      icon.topAnchor.constraint(equalTo: tile.topAnchor),
      icon.bottomAnchor.constraint(equalTo: tile.bottomAnchor),
      text.topAnchor.constraint(greaterThanOrEqualTo: margin.topAnchor),
      text.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor),
      text.centerYAnchor.constraint(equalTo: centerYAnchor),
      textSpacing,
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
    let compact = content.density == .compact
    directionalLayoutMargins = compact
      ? .init(top: 5, leading: 8, bottom: 5, trailing: 4)
      : .init(top: 11, leading: 16, bottom: 11, trailing: 4)
    textSpacing.constant = compact ? 8 : 12
    tileWidth.constant = compact ? 24 : 32
    tile.layer.cornerRadius = compact ? 6 : 9
    name.font = compact
      ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
      : .preferredFont(forTextStyle: .headline)
    path.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: compact ? .caption2 : .caption1).pointSize, weight: .regular)
    count.font = .preferredFont(forTextStyle: compact ? .caption1 : .footnote)
    text.spacing = compact ? 1 : 2
    let row = content.row
    let url = LodyListPhoto.url(row.image)
    photoURL = url
    tile.textColor = content.accent
    icon.tintColor = content.accent
    let photo = url.flatMap { source in
      LodyListPhoto.image(for: source, ready: { [weak self] image in
        guard let self, self.photoURL == source else { return }
        self.showTile(photo: image, symbol: nil, monogram: "", accent: content.accent)
      })
    }
    let symbol = url == nil && !row.image.isEmpty ? UIImage(systemName: row.image) : nil
    showTile(photo: photo, symbol: symbol, monogram: row.monogram, accent: content.accent)
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
    accessibilityLabel = content.accessibilityLabel
  }

  private func showTile(photo: UIImage?, symbol: UIImage?, monogram: String, accent: UIColor) {
    icon.image = photo ?? symbol
    icon.contentMode = photo == nil ? .center : .scaleAspectFill
    tile.text = icon.image == nil ? monogram : nil
    tile.backgroundColor = photo == nil ? accent.withAlphaComponent(0.14) : .clear
  }
}
