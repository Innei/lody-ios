import UIKit

struct ChatQuickReply: Decodable, Equatable {
  let id: String
  let label: String
  let message: String
}

struct ChatPreviewChip: Decodable, Equatable {
  struct Action: Decodable, Equatable {
    let id: String
    let title: String
    let symbol: String
    var destructive: Bool?
  }
  let label: String
  let symbol: String
  let state: String
  let accessibilityLabel: String
  var actions: [Action]?
}

final class ChatQuickRepliesView: UIScrollView {
  static var titleFont: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }
  static var chipHeight: CGFloat { titleFont.lineHeight + 16 }

  private let stack = UIStackView()
  private var rendered: [ChatQuickReply] = []
  private var renderedPreview: ChatPreviewChip?
  private var buttons: [UIButton] = []
  var onSelect: ((String) -> Void)?
  var onPreview: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-quick-replies"
    clipsToBounds = false
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = false
    isDirectionalLockEnabled = true
    contentInsetAdjustmentBehavior = .never
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func render(_ items: [ChatQuickReply], preview: ChatPreviewChip? = nil, visible: Bool, animated: Bool = false) {
    let showsReplies = visible && (!items.isEmpty || preview != nil)
    let visibilityChanged = isUserInteractionEnabled != showsReplies
    isUserInteractionEnabled = showsReplies
    accessibilityElementsHidden = !showsReplies
    if visibilityChanged {
      if showsReplies { isHidden = false }
      let update = { self.alpha = showsReplies ? 1 : 0 }
      if animated && window != nil && !UIAccessibility.isReduceMotionEnabled {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: update) { _ in
          self.isHidden = !self.isUserInteractionEnabled
        }
      } else {
        update()
        isHidden = !showsReplies
      }
    }
    guard items != rendered || preview != renderedPreview else { return }
    rendered = items
    renderedPreview = preview
    contentOffset = .zero
    for view in stack.arrangedSubviews { view.removeFromSuperview() }
    buttons.removeAll()
    if let preview { stack.addArrangedSubview(previewChip(preview)) }
    for item in items {
      stack.addArrangedSubview(chip(item))
    }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    let hit = super.hitTest(point, with: event)
    if let hit, hit !== self { return hit }
    for button in buttons where !button.isHidden {
      let frame = button.convert(button.bounds, to: self)
      let target = frame.insetBy(
        dx: -max(0, 44 - frame.width) / 2,
        dy: -max(0, 44 - frame.height) / 2
      )
      if target.contains(point) { return button }
    }
    return hit === self ? nil : hit
  }

  private func previewChip(_ preview: ChatPreviewChip) -> UIButton {
    var configuration = UIButton.Configuration.glass()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12)
    configuration.title = preview.label
    configuration.titleLineBreakMode = .byTruncatingMiddle
    configuration.imagePadding = 6
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: Self.titleFont, scale: .small)
    configuration.showsActivityIndicator = preview.state == "connecting"
    if preview.state != "connecting" { configuration.image = UIImage(systemName: preview.symbol) }
    configuration.baseForegroundColor = preview.state == "unavailable" ? .secondaryLabel : .systemBlue
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: Self.titleFont.pointSize, weight: .semibold)
      return outgoing
    }
    let button = UIButton(configuration: configuration)
    button.accessibilityIdentifier = "session-preview"
    button.accessibilityLabel = preview.accessibilityLabel
    button.addAction(UIAction { [weak self] _ in self?.onPreview?("open") }, for: .touchUpInside)
    if let actions = preview.actions, !actions.isEmpty {
      button.menu = UIMenu(children: actions.map { action in
        UIAction(title: action.title, image: UIImage(systemName: action.symbol),
                 attributes: action.destructive == true ? .destructive : []) { [weak self] _ in
          self?.onPreview?(action.id)
        }
      })
    }
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.heightAnchor.constraint(equalToConstant: Self.chipHeight),
      button.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
    ])
    buttons.append(button)
    return button
  }

  private func chip(_ item: ChatQuickReply) -> UIButton {
    var configuration = UIButton.Configuration.glass()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    configuration.title = item.label
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = Self.titleFont
      return outgoing
    }
    let button = UIButton(configuration: configuration)
    button.accessibilityIdentifier = "quick-reply:\(item.id)"
    button.accessibilityHint = LodyStrings.text("native.chat.quickReply.sendHint")
    button.addAction(UIAction { [weak self] _ in self?.onSelect?(item.id) }, for: .touchUpInside)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    let textWidth = (item.label as NSString).boundingRect(
      with: CGSize(width: .greatestFiniteMagnitude, height: Self.titleFont.lineHeight),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: Self.titleFont],
      context: nil
    ).width
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.heightAnchor.constraint(equalToConstant: Self.chipHeight),
      button.widthAnchor.constraint(equalToConstant: max(44, ceil(textWidth) + 24)),
    ])
    buttons.append(button)
    return button
  }
}
