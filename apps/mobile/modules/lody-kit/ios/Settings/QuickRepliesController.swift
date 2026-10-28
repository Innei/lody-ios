import UIKit

@MainActor
final class QuickRepliesController: UIViewController {
  private let list = LodyGroupedList(frame: .zero)
  private var observer: NSObjectProtocol?
  private var reordering = false
  private var replies: [QuickReply] = []

  init() {
    super.init(nibName: nil, bundle: nil)
    title = text("title")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.setPlaceholder(text("empty"))
    list.forwarded = { [weak self] name, body in self?.event(name, body) }
    view.addSubview(list)
    observer = NotificationCenter.default.addObserver(
      forName: .lodyPreferencesDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    renderHeader()
  }

  private func render() {
    replies = LodyPreferences.quickReplies
    list.setReordering(reordering)
    let rows = replies.map { reply in
      var row = LodyListRow.item(
        reply.id, reply.label, subtitle: reply.message, action: !reordering, disclosure: !reordering
      )
      var delete = LodyListAction()
      delete.id = "delete"
      delete.title = LodyStrings.text("common.delete")
      delete.symbol = "trash"
      delete.destructive = true
      row.actions = [delete]
      return row
    }
    list.setSections([.group("quick-replies", footer: text(reordering ? "reorderHint" : "hint"), rows)])
    renderHeader()
  }

  private func renderHeader() {
    guard let host = parent?.navigationItem else { return }
    let toggle = LodyStrings.text(reordering ? "common.done" : "common.edit")
    let edit = UIBarButtonItem(primaryAction: UIAction(title: toggle) { [weak self] _ in self?.toggleReordering() })
    edit.accessibilityLabel = toggle
    edit.isEnabled = reordering || replies.count >= 2
    let add = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "plus")) { [weak self] _ in
      self?.openEditor(nil)
    })
    add.accessibilityLabel = text("add")
    add.tintColor = .lodyAccent
    add.isEnabled = !reordering
    host.rightBarButtonItems = [add, edit]
  }

  private func toggleReordering() {
    reordering.toggle()
    render()
  }

  private func event(_ name: String, _ body: [String: Any]) {
    switch name {
    case "rowPress":
      guard let reply = replies.first(where: { $0.id == body["id"] as? String }) else { return }
      openEditor(reply)
    case "rowAction":
      guard body["actionId"] as? String == "delete", let id = body["id"] as? String else { return }
      confirmDelete(id)
    case "reorder":
      guard let ids = body["ids"] as? [String] else { return }
      reorder(ids)
    default:
      break
    }
  }

  private func openEditor(_ reply: QuickReply?) {
    let title = reply == nil ? text("add") : text("edit")
    LodyShell.shared.presentNative(QuickReplyEditorController(item: reply), title: title)
  }

  private func confirmDelete(_ id: String) {
    let alert = UIAlertController(title: text("deleteTitle"), message: text("deleteHint"), preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.delete"), style: .destructive) { [weak self] _ in
      guard let self, QuickReplyEditorController.save(replies.filter { $0.id != id }) else { return }
      reordering = false
      render()
    })
    present(alert, animated: true)
  }

  private func reorder(_ ids: [String]) {
    let byID = Dictionary(replies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard ids.count == replies.count, Set(ids).count == ids.count else { return }
    let ordered = ids.compactMap { byID[$0] }
    guard ordered.count == replies.count else { return }
    _ = QuickReplyEditorController.save(ordered)
  }

  private func text(_ key: String) -> String { LodyStrings.text("settings.quickReplies.\(key)") }
}
