import UIKit

open class CKAttachmentStrip: UIScrollView {
  public var onRemove: ((String) -> Void)?
  public var onPreview: ((String) -> Void)?
  private let stack = UIStackView()
  private var rendered: [CKAttachmentItem] = []
  private var pills: [String: CKGlassSurface] = [:]
  public var onHeightChange: (() -> Void)?
  public var hasVisiblePills: Bool { !pills.isEmpty }

  public var style: CKAttachmentStyle {
    didSet {
      let items = rendered
      for surface in pills.values {
        surface.onHidden = nil
        surface.removeFromSuperview()
      }
      pills.removeAll()
      rendered = []
      stack.spacing = max(0, style.spacing)
      render(items, animatedInsertion: false)
      onHeightChange?()
    }
  }

  public init(style: CKAttachmentStyle = CKAttachmentStyle()) {
    self.style = style
    super.init(frame: .zero)
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = false
    stack.axis = .horizontal
    stack.spacing = max(0, style.spacing)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
      stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
    ])
  }
  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public func render(_ items: [CKAttachmentItem], animatedRemoval: Bool = false, animatedInsertion: Bool = true) {
    guard items != rendered else { return }
    let previous = rendered
    rendered = items
    for (id, surface) in pills where !items.contains(where: { $0.id == id }) {
      surface.setVisible(false, animated: animatedRemoval)
    }
    for (index, item) in items.enumerated() {
      if let existing = pills[item.id], previous.contains(item) {
        stack.removeArrangedSubview(existing)
        stack.insertArrangedSubview(existing, at: min(index, stack.arrangedSubviews.count))
        existing.setVisible(true, animated: animatedInsertion)
        continue
      }
      // A restored draft may reuse an id while an old pill is leaving.
      if let previous = pills.removeValue(forKey: item.id) {
        previous.onHidden = nil
        previous.removeFromSuperview()
      }
      let surface = pill(item)
      pills[item.id] = surface
      surface.onHidden = { [weak self, weak surface] in
        guard let self, let surface, self.pills[item.id] === surface,
              !self.rendered.contains(where: { $0.id == item.id }) else { return }
        self.pills.removeValue(forKey: item.id)
        surface.removeFromSuperview()
        self.onHeightChange?()
      }
      stack.insertArrangedSubview(surface, at: min(index, stack.arrangedSubviews.count))
      surface.setVisible(true, animated: animatedInsertion)
    }
  }

  public func attachmentFrame(id: String) -> CGRect? {
    guard rendered.contains(where: { $0.id == id }), let view = pills[id] else { return nil }
    return view.convert(view.bounds, to: self)
  }

  public func snapshot(id: String) -> UIView? {
    guard rendered.contains(where: { $0.id == id }), let pill = pills[id] else { return nil }
    return pill.snapshotView(afterScreenUpdates: false)
  }

  private func pill(_ item: CKAttachmentItem) -> CKGlassSurface {
    var config = UIButton.Configuration.plain()
    config.image = item.thumbnail?.withRenderingMode(.alwaysOriginal) ?? UIImage(systemName: item.symbol)
    config.imagePadding = 5
    config.baseForegroundColor = style.theme.textColor
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12)
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 32)
    config.attributedTitle = AttributedString(item.name, attributes: AttributeContainer([
      .font: style.font,
    ]))
    config.titleLineBreakMode = .byTruncatingMiddle
    let button = UIButton(configuration: config)
    button.accessibilityLabel = item.previewAccessibilityLabel
    button.addAction(UIAction { [weak self] _ in self?.onPreview?(item.id) }, for: .touchUpInside)
    let remove = UIButton(type: .system)
    remove.setImage(UIImage(systemName: style.removeSymbol), for: .normal)
    remove.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 13), forImageIn: .normal)
    remove.tintColor = style.theme.mutedTextColor
    remove.accessibilityLabel = item.removeAccessibilityLabel
    remove.addAction(UIAction { [weak self] _ in self?.onRemove?(item.id) }, for: .touchUpInside)
    let surface = CKGlassSurface(interactive: true)
    if let radius = style.cornerRadius {
      surface.cornerConfiguration = .corners(radius: .fixed(max(0, radius)))
    } else {
      surface.cornerConfiguration = .capsule()
    }
    surface.tintColor = style.theme.tintColor
    surface.contentView.addSubview(button)
    surface.contentView.addSubview(remove)
    button.translatesAutoresizingMaskIntoConstraints = false
    remove.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: surface.contentView.topAnchor), button.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
      button.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor), button.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
      remove.topAnchor.constraint(equalTo: surface.contentView.topAnchor), remove.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
      remove.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -4),
      remove.widthAnchor.constraint(equalToConstant: 30),
      surface.widthAnchor.constraint(lessThanOrEqualToConstant: max(80, style.maximumWidth)),
      surface.heightAnchor.constraint(equalToConstant: max(34, style.height)),
    ])
    return surface
  }
}
