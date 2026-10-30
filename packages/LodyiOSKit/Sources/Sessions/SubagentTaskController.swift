import UIKit

@MainActor
final class SubagentTaskController: UIViewController {
  let entryId: String
  let itemId: String
  private var item: [String: Any]
  private let chat = LodyChatView(frame: .zero)
  private lazy var copyItem: UIBarButtonItem = {
    let copy = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), primaryAction: UIAction { [weak self] _ in self?.copyResult() })
    copy.accessibilityIdentifier = "subagent-detail-copy"
    copy.accessibilityLabel = String(localized: "subagent.detail.copy", bundle: .lody)
    return copy
  }()
  var onActivity: ((String, String) -> Void)?
  var onFile: ((String, Int) -> Void)?

  init(entryId: String, item: [String: Any]) {
    self.entryId = entryId; self.item = item; itemId = item["itemId"] as! String
    super.init(nibName: nil, bundle: nil)
    chat.setProcessEntryID(entryId); chat.setProcessStartID("__subagent__"); chat.setComposerState("{}")
    chat.setEmptyText(String(localized: "process.empty", bundle: .lody))
    chat.onActivityPress = { [weak self] body in
      guard let entry = body["entryId"] as? String, let item = body["itemId"] as? String else { return }
      self?.onActivity?(entry, item)
    }
    chat.onFilePress = { [weak self] body in
      guard let path = body["path"] as? String else { return }
      self?.onFile?(path, body["line"] as? Int ?? 0)
    }
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  var pageTitle: String {
    (item["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? actor
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    chat.frame = view.bounds; chat.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(chat)
    render()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    applyHeader()
  }

  func update(_ json: String) {
    if let next = SessionController.item(in: json, entryId: entryId, itemId: itemId) { item = next }
    if isViewLoaded { render() }
  }

  private var actor: String {
    (item["actor"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "native.chat.transcript.subtask", bundle: .lody)
  }

  private var status: String { item["status"] as? String ?? "" }

  private var result: String {
    (item[status == "failed" ? "error" : "summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var caption: String {
    let key = ["pending": "pending", "in_progress": "running", "completed": "completed", "failed": "failed"][status]
    var labels = [actor]
    if let key { labels.append(String(localized: String.LocalizationValue("native.chat.subagent." + key), bundle: .lody)) }
    if item["isBackgrounded"] as? Bool == true { labels.append(String(localized: "native.chat.subagent.background", bundle: .lody)) }
    if item["run"] == nil, let tool = item["lastToolName"] as? String, !tool.isEmpty {
      labels.append(String.localizedStringWithFormat(String(localized: "subagent.detail.lastToolInline", bundle: .lody), tool))
    }
    return labels.joined(separator: " · ")
  }

  private func applyHeader() {
    let host = parent ?? self
    let header = LodyNavigationHeader.of(host.navigationItem)
    header.title = pageTitle
    host.navigationItem.subtitle = caption
    let items = result.isEmpty ? [] : [copyItem]
    if header.rightItems != items { header.rightItems = items }
  }

  private func copyResult() {
    UIPasteboard.general.string = result
    LodyToastOverlay.shared.show(
      message: String(localized: "subagent.detail.copied", bundle: .lody), kind: "info",
      below: navigationController?.navigationBar
    )
  }

  private func render() {
    var items: [[String: Any]]
    var state: String
    if let run = item["run"] as? [String: Any] {
      items = run["items"] as? [[String: Any]] ?? []
      state = run["state"] as? String ?? ""
    } else {
      items = []
      state = status == "in_progress" ? "running" : status
    }
    if !result.isEmpty, !items.contains(where: { $0["type"] as? String == "text" && ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == result }) {
      items.append(["itemId": itemId + ":result", "type": "text", "text": result])
    }
    let entry: [String: Any] = ["id": entryId, "role": "assistant", "status": state,
      "finished": !["pending", "running", "in_progress"].contains(state), "items": items]
    let data = try! JSONSerialization.data(withJSONObject: [entry])
    chat.setEntries(String(decoding: data, as: UTF8.self)); chat.scheduleUpdate()
    if isViewLoaded, view.window != nil { applyHeader() }
  }
}
