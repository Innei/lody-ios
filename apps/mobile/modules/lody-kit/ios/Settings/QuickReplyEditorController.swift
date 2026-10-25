import UIKit

@MainActor
final class QuickReplyEditorController: LodyFormController {
  private let item: QuickReply?
  private let id: String
  private lazy var label = LodyFormField(id: "quick-reply-label", label: text("label"), text: item?.label, limit: 40)
  private lazy var message = LodyFormTextView(
    id: "quick-reply-message", label: text("message"), text: item?.message, limit: 32000, minHeight: 144
  )
  private lazy var saveItem = Self.barButton(title: LodyStrings.text("common.save"), label: LodyStrings.text("common.save"), prominent: true) {
    [weak self] in self?.commit()
  }

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
    label.clearButtonMode = .whileEditing
    label.changed = { [weak self] in self?.updateSave() }
    message.changed = { [weak self] in self?.updateSave() }
    stack.addArrangedSubview(LodyFormGroup(header: text("label"), label))
    stack.addArrangedSubview(LodyFormGroup(header: text("message"), footer: text("sendHint"), message))
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    header?.rightBarButtonItems = [saveItem]
    header?.leftBarButtonItems = [
      Self.barButton(title: LodyStrings.text("common.cancel"), label: LodyStrings.text("common.cancel")) { [weak self] in
        self?.closeForm()
      },
    ]
    updateSave()
  }

  private func updateSave() {
    saveItem.isEnabled = !label.trimmed.isEmpty && !message.trimmed.isEmpty
  }

  private func commit() {
    guard saveItem.isEnabled else { return }
    let reply = QuickReply(id: id, label: label.trimmed, message: message.text)
    let current = LodyPreferences.quickReplies
    let next = item == nil ? current + [reply] : current.map { $0.id == id ? reply : $0 }
    if Self.save(next) { closeForm() }
  }

  private func text(_ key: String) -> String { LodyStrings.text("settings.quickReplies.\(key)") }
}
