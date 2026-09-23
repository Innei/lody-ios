import UIKit

struct ChatQuickReply: Decodable, Equatable {
  let id: String
  let label: String
  let message: String
}

final class ChatQuickRepliesView: UIScrollView {
  static var titleFont: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }
  static var chipHeight: CGFloat { titleFont.lineHeight + 16 }

  private let stack = UIStackView()
  private var rendered: [ChatQuickReply] = []
  private var buttons: [UIButton] = []
  var onSelect: ((String) -> Void)?

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

  func render(_ items: [ChatQuickReply], visible: Bool) {
    isHidden = !visible || items.isEmpty
    accessibilityElementsHidden = isHidden
    guard items != rendered else { return }
    rendered = items
    contentOffset = .zero
    for view in stack.arrangedSubviews { view.removeFromSuperview() }
    buttons.removeAll()
    for item in items {
      stack.addArrangedSubview(chip(item))
    }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
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
