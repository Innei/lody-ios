import UIKit

@MainActor
class LodyFormController: UIViewController {
  let scroll = UIScrollView()
  let stack = UIStackView()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .lodyGroupedBackground
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.contentInsetAdjustmentBehavior = .automatic
    scroll.keyboardDismissMode = .interactive
    scroll.alwaysBounceVertical = true
    LodyScrollEdges.navigation(scroll)
    view.addSubview(scroll)
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
      stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
    ])
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    LodyScrollEdges.bind(scroll, to: self)
  }

  var header: UINavigationItem? { parent?.navigationItem }

  func closeForm() {
    view.endEditing(true)
    dismiss(animated: true)
  }

  static func barButton(
    title: String? = nil, symbol: String? = nil, label: String, prominent: Bool = false,
    action: @escaping @MainActor () -> Void
  ) -> UIBarButtonItem {
    let item = UIBarButtonItem(primaryAction: UIAction(title: title ?? "", image: symbol.flatMap { UIImage(systemName: $0) }) { _ in
      action()
    })
    item.accessibilityLabel = label
    if prominent {
      item.style = .prominent
      item.tintColor = .lodyAccent
    }
    return item
  }
}

final class LodyFormGroup: UIStackView {
  private let footerLabel = LodyFormGroup.caption()

  init(header: String? = nil, footer: String? = nil, _ content: UIView) {
    super.init(frame: .zero)
    axis = .vertical
    spacing = 7
    if let header {
      let title = Self.caption()
      title.text = header.uppercased()
      title.accessibilityTraits = .header
      addArrangedSubview(Self.inset(title))
    }
    let card = UIView()
    card.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
    }
    card.layer.cornerRadius = 26
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: card.topAnchor),
      content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
    ])
    addArrangedSubview(card)
    addArrangedSubview(Self.inset(footerLabel))
    self.footer = footer
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError() }

  var footer: String? {
    get { footerLabel.text }
    set {
      footerLabel.text = newValue
      footerLabel.superview?.isHidden = newValue?.isEmpty ?? true
    }
  }

  static func caption(color: UIColor = .secondaryLabel, size: CGFloat = 13) -> UILabel {
    let label = UILabel()
    label.font = .dynamic(of: size)
    label.textColor = color
    label.numberOfLines = 0
    return label
  }

  static func inset(_ label: UIView) -> UIView {
    let container = UIView()
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: container.topAnchor),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    ])
    return container
  }
}

final class LodyFormField: UITextField, UITextFieldDelegate {
  private let limit: Int
  var changed: (() -> Void)?

  init(id: String, label: String, text: String?, limit: Int) {
    self.limit = limit
    super.init(frame: .zero)
    self.text = text
    font = .dynamic(of: 17)
    textColor = .label
    autocorrectionType = .no
    accessibilityIdentifier = id
    accessibilityLabel = label
    delegate = self
    addAction(UIAction { [weak self] _ in self?.changed?() }, for: .editingChanged)
    heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func textRect(forBounds bounds: CGRect) -> CGRect {
    super.textRect(forBounds: bounds).inset(by: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
  }

  override func editingRect(forBounds bounds: CGRect) -> CGRect {
    super.editingRect(forBounds: bounds).inset(by: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
  }

  override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
    super.clearButtonRect(forBounds: bounds).offsetBy(dx: -10, dy: 0)
  }

  func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    (field.text ?? "").utf16.count - range.length + string.utf16.count <= limit
  }

  var trimmed: String { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

final class LodyFormTextView: UITextView, UITextViewDelegate {
  private let limit: Int
  var changed: (() -> Void)?

  init(id: String, label: String, text: String?, limit: Int, minHeight: CGFloat) {
    self.limit = limit
    super.init(frame: .zero, textContainer: nil)
    self.text = text
    font = .dynamic(of: 17)
    textColor = .label
    backgroundColor = .clear
    isScrollEnabled = false
    autocorrectionType = .no
    textContainer.lineFragmentPadding = 0
    textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
    accessibilityIdentifier = id
    accessibilityLabel = label
    delegate = self
    heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    textView.text.utf16.count - range.length + text.utf16.count <= limit
  }

  func textViewDidChange(_ textView: UITextView) {
    changed?()
  }

  var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

final class LodyFormToggle: UIView {
  let toggle = UISwitch()

  init(id: String, title: String, isOn: Bool) {
    super.init(frame: .zero)
    let label = UILabel()
    label.text = title
    label.font = .dynamic(of: 17)
    label.numberOfLines = 0
    label.isAccessibilityElement = false
    toggle.isOn = isOn
    toggle.onTintColor = .lodyAccent
    toggle.accessibilityIdentifier = id
    toggle.accessibilityLabel = title
    let row = UIStackView(arrangedSubviews: [label, toggle])
    row.alignment = .center
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}

enum LodyFormButton {
  static func make(id: String, title: String, destructive: Bool = false, action: @escaping @MainActor () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = destructive ? .systemRed : .lodyAccent
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var next = attributes
      next.font = .dynamic(of: 17)
      return next
    }
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.setTitle(title, for: .normal)
    button.accessibilityIdentifier = id
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }
}
