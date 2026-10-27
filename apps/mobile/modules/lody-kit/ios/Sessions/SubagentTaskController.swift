import UIKit

@MainActor
final class SubagentTaskController: UIViewController {
  let entryId: String
  let itemId: String
  private var item: [String: Any]
  private let chat = LodyChatView(appContext: nil)
  private let list = LodyGroupedList(appContext: nil)
  var onActivity: ((String, String) -> Void)?
  var onFile: ((String, Int) -> Void)?

  init(entryId: String, item: [String: Any]) {
    self.entryId = entryId; self.item = item; itemId = item["itemId"] as! String
    super.init(nibName: nil, bundle: nil)
    chat.setProcessEntryID(entryId); chat.setProcessStartID("__subagent__"); chat.setComposerState("{}")
    chat.setEmptyText(LodyStrings.text("process.empty"))
    chat.onActivityPress.onEventSent = { [weak self] body in
      guard let entry = body["entryId"] as? String, let item = body["itemId"] as? String else { return }
      self?.onActivity?(entry, item)
    }
    chat.onFilePress.onEventSent = { [weak self] body in
      guard let path = body["path"] as? String else { return }
      self?.onFile?(path, body["line"] as? Int ?? 0)
    }
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    for child in [chat, list] as [UIView] {
      child.frame = view.bounds; child.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(child)
    }
    list.forwarded = { [weak self] name, body in
      guard name == "rowPress", body["id"] as? String == "subagent-detail-copy", let self else { return }
      UIPasteboard.general.string = result
      LodyToastOverlay.shared.show(message: LodyStrings.text("subagent.detail.copied"), kind: "info")
    }
    render()
  }
  func update(_ json: String) {
    if let next = SessionController.item(in: json, entryId: entryId, itemId: itemId) { item = next }
    if isViewLoaded { render() }
  }
  private var result: String { (item[item["status"] as? String == "failed" ? "error" : "summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
  private func render() {
    let actor = (item["actor"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? LodyStrings.text("native.chat.transcript.subtask")
    let description = (item["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? actor
    let status = item["status"] as? String ?? ""
    let key = ["pending": "pending", "in_progress": "running", "completed": "completed", "failed": "failed"][status]
    var labels = [actor]
    if let key { labels.append(LodyStrings.text("native.chat.subagent." + key)) }
    if item["isBackgrounded"] as? Bool == true { labels.append(LodyStrings.text("native.chat.subagent.background")) }
    let subtitle = labels.joined(separator: " · ")
    if let run = item["run"] as? [String: Any] {
      var items = run["items"] as? [[String: Any]] ?? []
      if !result.isEmpty, !items.contains(where: { $0["type"] as? String == "text" && ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == result }) {
        items.append(["itemId": itemId + ":result", "type": "text", "text": result])
      }
      items.insert(["itemId": itemId + ":header", "type": "text", "text": subtitle + "\n\n" + description], at: 0)
      let state = run["state"] as? String ?? ""
      let entry: [String: Any] = ["id": entryId, "role": "assistant", "status": state,
        "finished": !["pending", "running", "in_progress"].contains(state), "items": items]
      let data = try! JSONSerialization.data(withJSONObject: [entry])
      chat.setEntries(String(decoding: data, as: UTF8.self)); chat.scheduleUpdate()
      list.isHidden = true; chat.isHidden = false
      return
    }
    chat.isHidden = true; list.isHidden = false
    let section = LodyListSection(); section.id = "task"
    let header = LodyListRow(); header.id = "subagent-header"; header.title = description; header.subtitle = subtitle
    section.rows = [header]
    if !result.isEmpty {
      let body = LodyListRow(); body.id = "subagent-detail-result"; body.title = result
      let copy = LodyListRow(); copy.id = "subagent-detail-copy"; copy.title = LodyStrings.text("subagent.detail.copy"); copy.action = true
      section.rows += [body, copy]
    }
    if let name = item["lastToolName"] as? String, !name.isEmpty {
      let tool = LodyListRow(); tool.id = "subagent-last-tool"; tool.title = LodyStrings.text("subagent.detail.lastTool"); tool.value = name
      section.rows.append(tool)
    }
    list.setSections([section])
  }
}
