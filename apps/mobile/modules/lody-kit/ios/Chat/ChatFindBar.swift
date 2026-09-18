import UIKit

final class ChatFindBar: UIView, UITextFieldDelegate {
  let field = UISearchTextField()
  private let count = UILabel()
  private let previous = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private let close = UIButton(type: .system)
  private let scope = UILabel()
  var preferredHeight: CGFloat { scope.isHidden ? 52 : 72 }
  var changed: (() -> Void)?
  var move: ((Int) -> Void)?
  var dismiss: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .systemBackground
    accessibilityIdentifier = "chat-find"
    field.placeholder = LodyStrings.text("native.chat.find.placeholder")
    field.accessibilityIdentifier = "chat-find-field"
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.returnKeyType = .search
    field.delegate = self
    field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    count.font = .preferredFont(forTextStyle: .footnote)
    count.textColor = .secondaryLabel
    count.accessibilityIdentifier = "chat-find-count"
    count.setContentCompressionResistancePriority(.required, for: .horizontal)
    configure(previous, symbol: "chevron.up", key: "previous", action: { [weak self] in self?.move?(-1) })
    configure(nextButton, symbol: "chevron.down", key: "next", action: { [weak self] in self?.move?(1) })
    configure(close, symbol: "xmark", key: "close", action: { [weak self] in self?.dismiss?() })
    let stack = UIStackView(arrangedSubviews: [field, count, previous, nextButton, close])
    stack.axis = .horizontal
    stack.spacing = 4
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    scope.font = .preferredFont(forTextStyle: .caption2)
    scope.textColor = .secondaryLabel
    scope.text = LodyStrings.text("native.chat.find.loadedOnly")
    scope.accessibilityIdentifier = "chat-find-scope"
    scope.isHidden = true
    scope.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scope)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.heightAnchor.constraint(equalToConstant: 44),
      field.heightAnchor.constraint(equalToConstant: 44),
      scope.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
      scope.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 2),
    ])
    isHidden = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func configure(_ button: UIButton, symbol: String, key: String, action: @escaping () -> Void) {
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.accessibilityIdentifier = "chat-find-" + key
    button.accessibilityLabel = LodyStrings.text("native.chat.find." + key)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
  }

  func update(current: Int, total: Int, partial: Bool) {
    if scope.isHidden != !partial { scope.isHidden = !partial; superview?.setNeedsLayout() }
    count.text = total == 0 ? LodyStrings.text("native.chat.find.noResults") : "\(current) / \(total)"
    if field.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { count.text = "" }
    count.accessibilityLabel = count.text
    count.accessibilityHint = partial ? LodyStrings.text("native.chat.find.loadedOnly") : nil
    field.accessibilityHint = partial ? LodyStrings.text("native.chat.find.loadedOnly") : nil
    previous.isEnabled = total > 0
    nextButton.isEnabled = total > 0
  }

  @objc private func textChanged() { changed?() }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool { move?(1); return false }
}
