import UIKit

@MainActor
final class QuickReplyEditorController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
  private let item: QuickReply?
  private let id: String
  private let scroll = UIScrollView()
  private let label = UITextField()
  private let message = UITextView()
  private lazy var saveItem = UIBarButtonItem(primaryAction: UIAction(title: LodyStrings.text("common.save")) { [weak self] _ in
    self?.commit()
  })

  init(item: QuickReply?) {
    self.item = item
    id = item?.id ?? "\(Int(Date().timeIntervalSince1970 * 1000))-\(String(UInt64.random(in: 0...UInt64.max), radix: 36))"
    super.init(nibName: nil, bundle: nil)
    title = text("edit")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  static func save(_ replies: [QuickReply]) -> Bool {
    if LodyPreferences.saveQuickReplies(replies) { return true }
    LodyToastOverlay.shared.show(message: LodyStrings.text("settings.quickReplies.saveFailed"), kind: "error")
    return false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .lodyGroupedBackground
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.contentInsetAdjustmentBehavior = .automatic
    scroll.keyboardDismissMode = .interactive
    scroll.alwaysBounceVertical = true
    LodyScrollEdges.navigation(scroll)
    view.addSubview(scroll)
    let stack = UIStackView(arrangedSubviews: [
      group(text("label"), footer: nil, field: label),
      group(text("message"), footer: text("sendHint"), field: message),
    ])
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
      message.heightAnchor.constraint(greaterThanOrEqualToConstant: 144),
    ])
    configureFields()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    LodyScrollEdges.bind(scroll, to: self)
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    guard let host = parent?.navigationItem else { return }
    saveItem.style = .prominent
    saveItem.tintColor = .lodyAccent
    saveItem.accessibilityLabel = LodyStrings.text("common.save")
    host.rightBarButtonItems = [saveItem]
    host.leftBarButtonItems = [
      UIBarButtonItem(primaryAction: UIAction(title: LodyStrings.text("common.cancel")) { [weak self] _ in self?.close() }),
    ]
    updateSave()
  }

  private func configureFields() {
    let font = UIFont.dynamic(of: 17)
    label.text = item?.label
    label.font = font
    label.textColor = .label
    label.clearButtonMode = .whileEditing
    label.autocorrectionType = .no
    label.accessibilityIdentifier = "quick-reply-label"
    label.accessibilityLabel = text("label")
    label.delegate = self
    label.addAction(UIAction { [weak self] _ in self?.updateSave() }, for: .editingChanged)
    label.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    message.text = item?.message
    message.font = font
    message.textColor = .label
    message.backgroundColor = .clear
    message.isScrollEnabled = false
    message.textContainer.lineFragmentPadding = 0
    message.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
    message.accessibilityIdentifier = "quick-reply-message"
    message.accessibilityLabel = text("message")
    message.delegate = self
  }

  private func group(_ header: String, footer: String?, field: UIView) -> UIView {
    let card = UIView()
    card.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
    }
    card.layer.cornerRadius = 26
    card.layer.cornerCurve = .continuous
    card.clipsToBounds = true
    field.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(field)
    NSLayoutConstraint.activate([
      field.topAnchor.constraint(equalTo: card.topAnchor),
      field.bottomAnchor.constraint(equalTo: card.bottomAnchor),
      field.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
    ])
    let title = caption(header.uppercased())
    title.accessibilityTraits = .header
    let stack = UIStackView(arrangedSubviews: [title, card] + (footer.map { [caption($0)] } ?? []))
    stack.axis = .vertical
    stack.spacing = 7
    return stack
  }

  private func caption(_ value: String) -> UIView {
    let caption = UILabel()
    caption.text = value
    caption.font = .dynamic(of: 13)
    caption.textColor = .secondaryLabel
    caption.numberOfLines = 0
    let container = UIView()
    caption.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(caption)
    NSLayoutConstraint.activate([
      caption.topAnchor.constraint(equalTo: container.topAnchor),
      caption.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      caption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      caption.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
    ])
    return container
  }

  func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    (field.text ?? "").utf16.count - range.length + string.utf16.count <= 40
  }

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    textView.text.utf16.count - range.length + text.utf16.count <= 32000
  }

  func textViewDidChange(_ textView: UITextView) {
    updateSave()
  }

  private var trimmedLabel: String { (label.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

  private func updateSave() {
    saveItem.isEnabled = !trimmedLabel.isEmpty && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func commit() {
    guard saveItem.isEnabled else { return }
    let reply = QuickReply(id: id, label: trimmedLabel, message: message.text)
    let current = LodyPreferences.quickReplies
    let next = item == nil ? current + [reply] : current.map { $0.id == id ? reply : $0 }
    if Self.save(next) { close() }
  }

  private func close() {
    view.endEditing(true)
    dismiss(animated: true)
  }

  private func text(_ key: String) -> String { LodyStrings.text("settings.quickReplies.\(key)") }
}
