import LodyCore
import UIKit

@MainActor
final class SessionActions {
  private static var deleting: Set<String> = []
  private let source: SessionSource

  init(source: SessionSource) {
    self.source = source
  }

  static func isDeleting(_ workspaceId: String, _ sessionId: String) -> Bool {
    deleting.contains("\(workspaceId):\(sessionId)")
  }

  func open(_ rowId: String, findQuery: String? = nil, from controller: UIViewController) {
    if rowId.hasPrefix("project:") {
      let params = Self.json(["projectId": String(rowId.dropFirst(8))])
      LodyShell.shared.openPage("project", params: params, from: controller)
      return
    }
    let state = source.state
    guard state.catalog.session(rowId) != nil, let session = source.raw(rowId) else { return }
    var intent: [String: Any] = ["workspaceId": state.workspaceId, "session": session]
    if let findQuery, !findQuery.isEmpty { intent["findQuery"] = findQuery }
    LodyShell.shared.sessionIntent("open", intent)
  }

  static func create(_ fields: [String: Any]) {
    var intent = fields
    if SessionCatalogPreview.state != nil { intent["catalog"] = SessionCatalogPreview.catalogJSON }
    LodyShell.shared.sessionIntent("create", intent)
  }

  func perform(_ actionId: String, row id: String, from controller: UIViewController) {
    let state = source.state
    guard !state.workspaceId.isEmpty else { return }
    switch actionId {
    case "copyPath":
      return
    case "open":
      open(SessionRows.projectId(ofRow: id).map { "project:\($0)" } ?? id, from: controller)
    case "newChat":
      Self.create(["workspaceId": state.workspaceId, "context": "chat"])
    case "newSession":
      let session = state.catalog.session(id)
      var intent: [String: Any] = ["workspaceId": state.workspaceId]
      if let session, SessionRows.isChat(session.projectId) {
        Self.create(intent)
        return
      }
      if let project = SessionRows.projectId(ofRow: id) ?? session?.projectId { intent["projectId"] = project }
      Self.create(intent)
    case "share":
      LodyShell.shared.sessionIntent("share", ["workspaceId": state.workspaceId, "sessionId": id])
    default:
      guard let session = state.catalog.session(id) else { return }
      sessionAction(actionId, session, in: state, from: controller)
    }
  }

  private func sessionAction(_ actionId: String, _ session: SessionItem, in state: SessionListState, from controller: UIViewController) {
    let workspace = state.workspaceId
    switch actionId {
    case "delete":
      confirmDeletion(session, in: state, from: controller)
    case "archive":
      let archived = !session.archived
      write(workspace, session.id, .archive(archived)) { failed in
        let key = archived ? "archive" : "unarchive"
        Self.toast(failed ? "\(key)Failed" : "\(key)d")
      }
    case "pin":
      let pinned = !session.pinned
      write(workspace, session.id, .pin(pinned)) { failed in
        if failed { Self.toast(pinned ? "pinFailed" : "unpinFailed") }
      }
    case "read":
      guard let message = session.lastMessageAt, (session.lastReadAt ?? -.infinity) < message else { return }
      write(workspace, session.id, .read(max(LodyRelativeTime.now(), message))) { failed in
        if failed { Self.toast("readFailed") }
      }
    case "rename":
      promptRename(session, workspace: workspace, from: controller)
    default:
      break
    }
  }

  private func write(_ workspace: String, _ id: String, _ change: SessionWrite, done: @escaping @MainActor (Bool) -> Void) {
    Task { [source] in
      do {
        try await source.write(workspace, id, change)
        done(false)
      } catch {
        done(true)
      }
    }
  }

  private func promptRename(_ session: SessionItem, workspace: String, from controller: UIViewController) {
    let title = LodyStrings.text("session.action.rename")
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addTextField { $0.text = session.title }
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak alert] _ in
      let next = String((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      guard !next.isEmpty else { return }
      self?.write(workspace, session.id, .rename(next)) { failed in
        if failed { Self.toast("renameFailed") }
      }
    })
    controller.present(alert, animated: true)
  }

  private func confirmDeletion(_ session: SessionItem, in state: SessionListState, from controller: UIViewController) {
    let targets = SessionRows.deletionTargets(state.catalog.sessions, id: session.id)
    let ids = targets.map(\.id)
    let keys = ids.map { "\(state.workspaceId):\($0)" }
    guard Self.deleting.isDisjoint(with: keys) else { return }
    let title = LodyStrings.text("session.delete.title")
    if SessionRows.deletionBlocked(targets) {
      let alert = UIAlertController(title: title, message: LodyStrings.text("session.delete.busy"), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default))
      controller.present(alert, animated: true)
      return
    }
    var message = targets.count > 1
      ? LodyStrings.text("session.delete.withTabs", ["title": session.title, "count": targets.count - 1])
      : LodyStrings.text("session.delete.message", ["title": session.title])
    if !SessionRows.isChat(session.projectId) { message += "\n\n" + LodyStrings.text("session.delete.worktree") }
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: LodyStrings.text("session.action.delete"), style: .destructive) { [weak self] _ in
      guard let self, Self.deleting.isDisjoint(with: keys) else { return }
      Self.deleting.formUnion(keys)
      LodyToastOverlay.shared.show(message: LodyStrings.text("session.delete.pending"), kind: "info")
      self.write(state.workspaceId, session.id, .delete(ids)) { failed in
        Self.deleting.subtract(keys)
        if failed {
          LodyToastOverlay.shared.show(message: LodyStrings.text("session.delete.failed"), kind: "error")
        } else {
          LodyToastOverlay.shared.show(message: LodyStrings.text("session.delete.success"), kind: "info")
        }
      }
    })
    controller.present(alert, animated: true)
  }

  private static func toast(_ key: String) {
    LodyToastOverlay.shared.show(message: LodyStrings.text("session.toast.\(key)"), kind: "error")
  }

  private static func json(_ object: [String: Any]) -> String {
    (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }

  static func cloud(_ workspaceId: String, _ sessionId: String, _ write: SessionWrite) async throws {
    guard let runtime = DataRuntime.current, runtime.workspace == workspaceId else {
      throw DataRuntime.failure("not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
    }
    switch write {
    case .archive(let archived):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.ArchiveSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, archived: archived)
      }
    case .pin(let pinned):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.PinSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, pinned: pinned)
      }
    case .read(let at):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.MarkSessionRead.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, lastReadAt: at)
      }
    case .rename(let title):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.RenameSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, title: title)
      }
    case .delete(let ids):
      let payload = json(["workspaceId": workspaceId, "sessionId": sessionId, "sessionIds": ids])
      guard OutboxSession.shared.allowsDeletion(payload) else {
        throw DataRuntime.failure("session_has_pending_send", "session_has_pending_send")
      }
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.DeleteSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, sessionIds: ids)
      }
    }
  }
}
