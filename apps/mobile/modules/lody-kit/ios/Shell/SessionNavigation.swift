import LodyCore
import UIKit

@MainActor
enum SessionNavigation {
  static func receive(_ json: String) throws {
    let fields = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    try handle(fields["kind"] as! String, fields)
  }

  @discardableResult
  static func handle(_ action: String, _ fields: [String: Any]) throws -> LodyPageController? {
    let source = HomeController.current?.source ?? .live
    let state = source.state
    if let workspace = fields["workspaceId"] as? String, workspace != state.workspaceId { throw OutboxError.scopeExpired }
    if let user = fields["userId"] as? String, user != state.userId { throw OutboxError.scopeExpired }
    switch action {
    case "open":
      let object: [String: Any]
      if let raw = fields["session"] as? String {
        object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
      } else { object = fields["session"] as! [String: Any] }
      let id = object["id"] as! String
      guard state.catalog.session(id) != nil else { throw OutboxError.scopeExpired }
      open(id, query: fields["findQuery"] as? String ?? "", source: source)
    case "share":
      let id = fields["sessionId"] as! String
      guard state.catalog.session(id) != nil else { throw OutboxError.scopeExpired }
      let content = LodyNativePages.make("session-share", params: SessionController.json(["workspaceId": state.workspaceId, "sessionId": id]))!
      LodyShell.shared.presentNative(content, title: LodyStrings.text("share.title"), grabber: true)
    case "create":
      var params = CreateSessionHostParams()
      params.userId = state.userId; params.workspaceId = state.workspaceId
      let index = UserDefaults.standard.integer(forKey: "inboxProjectSort")
      let sort = InboxSort.allCases.indices.contains(index) ? InboxSort.allCases[index] : .name
      params.projects = InboxSections.sortProjects(state.catalog.projects, sessions: state.catalog.sessions, sort: sort).filter { !SessionRows.isChat($0.id) }.map {
        CreateProject(id: $0.id, machineId: $0.machineId, name: $0.name, rootPath: $0.rootPath)
      }
      params.machineNames = state.catalog.machineNames
      params.projectId = fields["projectId"] as? String; params.context = fields["context"] as? String
      let draft = fields["draft"] as? [String: Any]
      params.initialText = draft?["text"] as? String
      params.initialAttachmentsJSON = draft?["attachmentsJSON"] as? String
      params.relay = true
      let content = CreateSessionHostController(params: params)
      content.onCreated = { created in
        guard source.state.key == state.key else { throw OutboxError.scopeExpired }
        let session = created["session"] as! [String: Any]
        guard source.state.catalog.session(session["id"] as! String) != nil else { throw OutboxError.scopeExpired }
        let choice = ModelChoice(modelId: created["modelId"] as? String, effort: created["effort"] as? String, modeId: created["modeId"] as? String)
        open(session["id"] as! String, choice: choice, source: source)
      }
      let regular = HomeController.current?.traitCollection.horizontalSizeClass == .regular
      if !regular, let label = fields["zoomSourceLabel"] as? String { LodySheetZoom.prepare(sourceLabel: label) }
      return LodyShell.shared.presentNative(content, title: LodyStrings.text("create.title"),
        detents: regular ? [1] : [0.62, 1], grabber: !regular, headerShown: false)
    default: preconditionFailure("Unknown session navigation: \(action)")
    }
    return nil
  }

  private static func open(_ id: String, query: String = "", choice: ModelChoice? = nil, source: SessionSource) {
    if let home = HomeController.current { home.openSession(id, query: query, choice: choice); return }
    let page = SessionController(sessionId: id, findQuery: query, choice: choice, source: source)
    LodyShell.shared.pushRootNative(page, title: "")
  }
}
