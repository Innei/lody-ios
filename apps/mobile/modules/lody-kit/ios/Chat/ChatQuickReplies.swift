import UIKit

struct ChatQuickReply: Decodable, Equatable {
  let id: String
  let label: String
  let message: String
}

final class ChatQuickRepliesView: UIScrollView {
  private let stack = UIStackView()
  private var rendered: [ChatQuickReply] = []
  var onSelect: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-quick-replies"
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    stack.axis = .horizontal
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
    for item in items {
      var configuration = UIButton.Configuration.glass()
      configuration.cornerStyle = .capsule
      configuration.title = item.label
      configuration.baseForegroundColor = .label
      configuration.contentInsets = .init(top: 8, leading: 14, bottom: 8, trailing: 14)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var value = attributes
        value.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return value
      }
      let button = UIButton(configuration: configuration)
      button.accessibilityIdentifier = "quick-reply:\(item.id)"
      button.accessibilityHint = LodyStrings.text("native.chat.quickReply.sendHint")
      button.addAction(UIAction { [weak self] _ in self?.onSelect?(item.id) }, for: .touchUpInside)
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
  }
}
