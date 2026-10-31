import UIKit

@MainActor
final class InboxProjectBar: UIView {
  static let height: CGFloat = 52

  var selected: ((String) -> Void)?
  private let scroll = UIScrollView()
  private let stack = UIStackView()
  private var chips: [InboxProjectChip] = []
  private var current = InboxSections.allFilter

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "project-bar"
    accessibilityLabel = String(localized: "inbox.projectBar.accessibility", bundle: .lody)
    accessibilityContainerType = .semanticGroup
    scroll.showsHorizontalScrollIndicator = false
    scroll.alwaysBounceHorizontal = true
    scroll.clipsToBounds = false
    stack.axis = .horizontal
    stack.spacing = 8
    stack.alignment = .center
    addSubview(scroll)
    scroll.addSubview(stack)
    for view in [scroll, stack] { view.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func update(_ chips: [InboxProjectChip], selected: String) {
    let all = InboxProjectChip(id: InboxSections.allFilter, title: String(localized: "inbox.filter.all", bundle: .lody))
    let next = [all] + chips
    guard next != self.chips || selected != current else { return }
    let rebuilt = next.map(\.id) != self.chips.map(\.id)
    self.chips = next
    current = selected
    if rebuilt {
      stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
      for chip in next {
        let view = InboxProjectChipView()
        view.addAction(UIAction { [weak self] _ in self?.selected?(chip.id) }, for: .touchUpInside)
        stack.addArrangedSubview(view)
      }
    }
    for (view, chip) in zip(stack.arrangedSubviews.compactMap { $0 as? InboxProjectChipView }, next) {
      view.configure(chip, selected: chip.id == selected)
    }
  }
}

@MainActor
private final class InboxProjectChipView: UIControl {
  private let glass = UIVisualEffectView(effect: UIGlassEffect())
  private let fill = UIView()
  private let glyph = LodyStatusGlyphView(kind: .none)
  private let title = UILabel()
  private let count = UILabel()
  private let row = UIStackView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = true
    accessibilityTraits = .button
    glass.cornerConfiguration = .capsule()
    glass.isUserInteractionEnabled = false
    fill.backgroundColor = .lodyInk
    fill.layer.cornerCurve = .continuous
    fill.isUserInteractionEnabled = false
    title.font = LodyDesign.font(.subheadline, size: 14, weight: .medium)
    title.adjustsFontForContentSizeCategory = true
    count.font = LodyDesign.mono(12)
    count.adjustsFontForContentSizeCategory = true
    row.axis = .horizontal
    row.spacing = 6
    row.alignment = .center
    row.isUserInteractionEnabled = false
    for view in [glyph, title, count] { row.addArrangedSubview(view) }
    for view in [glass, fill, row] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 44),
      glass.leadingAnchor.constraint(equalTo: leadingAnchor),
      glass.trailingAnchor.constraint(equalTo: trailingAnchor),
      glass.centerYAnchor.constraint(equalTo: centerYAnchor),
      glass.heightAnchor.constraint(equalToConstant: 36),
      fill.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
      fill.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
      fill.topAnchor.constraint(equalTo: glass.topAnchor),
      fill.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      row.centerYAnchor.constraint(equalTo: centerYAnchor),
      glyph.widthAnchor.constraint(equalToConstant: 12),
      glyph.heightAnchor.constraint(equalToConstant: 12),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    fill.layer.cornerRadius = glass.bounds.height / 2
  }

  override var isHighlighted: Bool {
    didSet { row.alpha = isHighlighted ? 0.5 : 1 }
  }

  func configure(_ chip: InboxProjectChip, selected: Bool) {
    accessibilityIdentifier = "project-chip:\(chip.id.isEmpty ? "all" : chip.id)"
    fill.isHidden = !selected
    glass.isHidden = selected
    title.text = chip.title
    title.textColor = selected ? .lodyGround : .lodyInk
    count.textColor = selected ? .lodyGround.withAlphaComponent(0.7) : .lodySecondary
    glyph.kind = Self.kind(chip.state)
    glyph.isHidden = chip.state == nil
    count.text = chip.count > 0 ? String(chip.count) : nil
    count.isHidden = chip.count == 0
    let status = chip.state.map {
      String.localizedStringWithFormat(String(localized: String.LocalizationValue("inbox.project." + $0.rawValue), bundle: .lody), chip.count)
    }
    accessibilityLabel = [chip.title, status].compactMap { $0 }.joined(separator: ", ")
    accessibilityTraits = selected ? [.button, .selected] : .button
  }

  private static func kind(_ state: SessionState?) -> LodyStatusGlyph.Kind {
    switch state {
    case .failed: .failed
    case .attention: .attention
    case .live: .live
    default: .none
    }
  }
}
