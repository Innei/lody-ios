import UIKit

final class ChatInputChrome: UIView {
  enum Status: String {
    case none = ""
    case connecting
    case paused
  }

  static let spacing: CGFloat = 22
  static let controlSize: CGFloat = 44
  static let scrollSize: CGFloat = 22

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

  private let container: UIVisualEffectView
  private let statusSurface: UIVisualEffectView
  private let scrollSurface: UIVisualEffectView
  private let statusButton = UIButton(type: .system)
  private let scrollButton = UIButton(type: .system)
  private let stack = UIStackView()

  override init(frame: CGRect) {
    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = Self.spacing
    container = UIVisualEffectView(effect: containerEffect)
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
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = Self.spacing
    stack.addArrangedSubview(statusSurface)
    stack.addArrangedSubview(scrollSurface)
    addSubview(container)
    container.contentView.addSubview(stack)
    statusSurface.contentView.addSubview(statusButton)
    scrollSurface.contentView.addSubview(scrollButton)
    [container, stack, statusSurface, scrollSurface, statusButton, scrollButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
    }
    var statusConfiguration = UIButton.Configuration.plain()
    statusConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
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
    scrollConfiguration.image = UIImage(systemName: "arrow.down")
    scrollConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 10,
      weight: .semibold
    )
    scrollConfiguration.baseForegroundColor = .label
    scrollButton.configuration = scrollConfiguration
    scrollButton.accessibilityLabel = LodyStrings.text("native.chat.scrollToBottom")
    scrollButton.accessibilityIdentifier = "chat-scroll-to-bottom"
    scrollButton.addAction(UIAction { [weak self] _ in self?.onScrollToBottom?() }, for: .touchUpInside)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: leadingAnchor),
      container.trailingAnchor.constraint(equalTo: trailingAnchor),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: container.contentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
      statusSurface.heightAnchor.constraint(equalToConstant: Self.controlSize),
      scrollSurface.widthAnchor.constraint(equalToConstant: Self.scrollSize),
      scrollSurface.heightAnchor.constraint(equalToConstant: Self.scrollSize),
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

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let pad = (Self.controlSize - Self.scrollSize) / 2
    if bounds.insetBy(dx: -pad, dy: -pad).contains(point) { return true }
    return super.point(inside: point, with: event)
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, isUserInteractionEnabled, scrollVisible else {
      return super.hitTest(point, with: event)
    }
    let pad = (Self.controlSize - Self.scrollSize) / 2
    let target = scrollButton.convert(scrollButton.bounds.insetBy(dx: -pad, dy: -pad), to: self)
    if target.contains(point) { return scrollButton }
    return super.hitTest(point, with: event)
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
