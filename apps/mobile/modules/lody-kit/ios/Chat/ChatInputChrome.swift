import UIKit

final class ChatInputChrome: UIView {
  enum Status: String {
    case none = ""
    case connecting
    case paused
  }

  static let controlSize: CGFloat = 44

  var status = Status.none {
    didSet {
      guard oldValue != status else { return }
      apply()
    }
  }
  var scrollVisible = false {
    didSet {
      guard oldValue != scrollVisible else { return }
      apply()
    }
  }
  var onReconnect: (() -> Void)?
  var onScrollToBottom: (() -> Void)?

  private let statusSurface: UIVisualEffectView
  private let scrollSurface: UIVisualEffectView
  private let statusButton = UIButton(type: .system)
  private let scrollButton = UIButton(type: .system)

  override init(frame: CGRect) {
    let statusGlass = UIGlassEffect(style: .regular)
    statusGlass.isInteractive = true
    statusSurface = UIVisualEffectView(effect: statusGlass)
    let scrollGlass = UIGlassEffect(style: .regular)
    scrollGlass.isInteractive = true
    scrollSurface = UIVisualEffectView(effect: scrollGlass)
    super.init(frame: frame)
    isHidden = true
    isUserInteractionEnabled = false
    statusSurface.cornerConfiguration = .capsule()
    scrollSurface.cornerConfiguration = .capsule()
    addSubview(statusSurface)
    addSubview(scrollSurface)
    statusSurface.contentView.addSubview(statusButton)
    scrollSurface.contentView.addSubview(scrollButton)
    [statusSurface, scrollSurface, statusButton, scrollButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
    }
    var statusConfiguration = UIButton.Configuration.plain()
    statusConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    statusConfiguration.titleLineBreakMode = .byTruncatingTail
    statusConfiguration.baseForegroundColor = .label
    statusConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.preferredFont(forTextStyle: .subheadline)
      return outgoing
    }
    statusButton.configuration = statusConfiguration
    statusButton.accessibilityIdentifier = "chat-connection-status"
    statusButton.setContentHuggingPriority(.required, for: .horizontal)
    statusSurface.setContentHuggingPriority(.required, for: .horizontal)
    statusButton.addAction(UIAction { [weak self] _ in
      guard self?.status == .paused else { return }
      self?.onReconnect?()
    }, for: .touchUpInside)
    var scrollConfiguration = UIButton.Configuration.plain()
    scrollConfiguration.contentInsets = .zero
    scrollConfiguration.image = UIImage(systemName: "arrow.down")
    scrollConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
      weight: .semibold
    )
    scrollConfiguration.baseForegroundColor = .label
    scrollButton.configuration = scrollConfiguration
    scrollButton.accessibilityLabel = LodyStrings.text("native.chat.scrollToBottom")
    scrollButton.accessibilityIdentifier = "chat-scroll-to-bottom"
    scrollButton.addAction(UIAction { [weak self] _ in self?.onScrollToBottom?() }, for: .touchUpInside)
    NSLayoutConstraint.activate([
      statusSurface.centerXAnchor.constraint(equalTo: centerXAnchor),
      statusSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
      statusSurface.trailingAnchor.constraint(lessThanOrEqualTo: scrollSurface.leadingAnchor, constant: -8),
      scrollSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollSurface.widthAnchor.constraint(equalTo: scrollSurface.heightAnchor),
      scrollSurface.heightAnchor.constraint(equalTo: statusSurface.heightAnchor),
      statusButton.leadingAnchor.constraint(equalTo: statusSurface.contentView.leadingAnchor),
      statusButton.trailingAnchor.constraint(equalTo: statusSurface.contentView.trailingAnchor),
      statusButton.topAnchor.constraint(equalTo: statusSurface.contentView.topAnchor),
      statusButton.bottomAnchor.constraint(equalTo: statusSurface.contentView.bottomAnchor),
      scrollButton.leadingAnchor.constraint(equalTo: scrollSurface.contentView.leadingAnchor),
      scrollButton.trailingAnchor.constraint(equalTo: scrollSurface.contentView.trailingAnchor),
      scrollButton.topAnchor.constraint(equalTo: scrollSurface.contentView.topAnchor),
      scrollButton.bottomAnchor.constraint(equalTo: scrollSurface.contentView.bottomAnchor),
    ])
    apply(animated: false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
    for button in [scrollButton, statusButton] {
      let visible = button === scrollButton ? scrollVisible : status == .paused
      guard visible else { continue }
      let bounds = button.bounds
      let target = bounds.insetBy(
        dx: -max(0, Self.controlSize - bounds.width) / 2,
        dy: -max(0, Self.controlSize - bounds.height) / 2
      )
      if target.contains(button.convert(point, from: self)) { return button }
    }
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }

  private func apply(animated: Bool? = nil) {
    let showStatus = status != .none
    let showScroll = scrollVisible
    let active = showStatus || showScroll
    var configuration = statusButton.configuration ?? .plain()
    let title = status == .paused
      ? LodyStrings.text("native.chat.connection.paused")
      : LodyStrings.text("native.chat.connection.connecting")
    configuration.title = title
    statusButton.configuration = configuration
    statusButton.accessibilityLabel = title
    statusButton.accessibilityTraits = status == .paused ? .button : .staticText
    statusButton.isUserInteractionEnabled = status == .paused
    let shouldAnimate = (animated ?? (window != nil && !UIAccessibility.isReduceMotionEnabled))
      && UIView.areAnimationsEnabled
    let updates = {
      self.statusSurface.isHidden = !showStatus
      self.scrollSurface.isHidden = !showScroll
      self.statusSurface.accessibilityElementsHidden = !showStatus
      self.scrollSurface.accessibilityElementsHidden = !showScroll
      self.isHidden = !active
      self.isUserInteractionEnabled = active
      self.superview?.layoutIfNeeded()
    }
    if shouldAnimate {
      UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: updates)
    } else {
      updates()
    }
  }
}
