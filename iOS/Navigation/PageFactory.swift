import UIKit

@MainActor
enum PageFactory {
  static var debugSceneFactory: ((String, [String: Any]) -> UIViewController?)?

  private static let factories: [String: ([String: Any]) -> UIViewController] = [
    "home": { _ in HomeController() },
    "pull-request": { params in
      let repository = params["repository"] as! String
      let number = params["number"] as! Int
      let scope = SettingsActor.live(params)
      let store = PullRequestStore(repository: repository, number: number, scope: scope,
        service: .live(workspaceId: scope.workspaceId, repository: repository, number: number))
      let page = PullRequestController(store: store)
      page.investigate = { [weak page] text in
        guard let page else { throw PullRequestStore.failure("unavailable") }
        try await LodyShell.shared.callback(from: page, name: "onInvestigate", value: text)
      }
      return page
    },
    "files": { params in
      FilesController(params: .init(workspaceId: params["workspaceId"] as! String, sessionId: params["sessionId"] as! String,
        relativePath: params["path"] as! String, userId: params["userId"] as! String))
    },
    "file-content": { params in
      let sessionId = params["sessionId"] as! String
      return FileContentController(sessionId: sessionId, path: params["path"] as! String, line: params["line"] as? Int,
        preview: params["preview"] as? Bool ?? false, feedback: .live(sessionId: sessionId))
    },
    "file-diff": { params in
      let sessionId = params["sessionId"] as! String
      return FileDiffController(request: .init(sessionId: sessionId, entryId: params["entryId"] as? String, path: params["path"] as! String),
        feedback: .live(sessionId: sessionId))
    },
    "workspace-changes": { params in
      let sessionId = params["sessionId"] as! String
      return WorkspaceChangesController(sessionId: sessionId, feedback: .live(sessionId: sessionId))
    },
    "appearance-settings": { _ in AppearanceController() },
    "app-icon": { _ in AppIconController() },
    "about": { _ in AboutController() },
    "preferences": { _ in PreferencesController() },
    "quick-reply-editor": { params in QuickReplyEditorController(item: QuickReply(params["item"])) },
    "ai-usage": { _ in AIUsageController() },
    "project-visibility": { _ in ProjectVisibilityController() },
    "github-settings": { _ in GitHubSettingsController() },
    "prompt-shortcuts": { _ in PromptShortcutsController() },
    "agent-roles": { _ in AgentRolesController() },
    "settings": { _ in SettingsController() },
    "archived-sessions": { _ in ArchivedSessionsController() },
    "workspace-editor": { params in WorkspaceEditorController(params: params) },
    "session": { params in SessionController(params: params) },
    "session-permission": { params in
      let sessionId = params["sessionId"] as! String
      return PermissionController(sessionId: sessionId, source: .live(sessionId: sessionId))
    },
    "memory-settings": { params in MemorySettingsController(scope: .live(params)) },
    "published-shares": { params in PublishedSharesController(scope: .live(params)) },
    "remote-settings": { params in RemoteSettingsController(kind: params["kind"] as? String ?? "machine", scope: .live(params)) },
    "diagnostics": { _ in DiagnosticsController() },
    "picker": { params in PageFactory.picker(params) },
    "project-history": { params in ProjectHistoryController(scope: .live(params)) },
    "project": { params in ProjectController(projectId: params["projectId"] as? String ?? "") },
    "activity": { params in
      ActivityController(workspaceId: params["workspaceId"] as? String ?? "", userId: params["userId"] as? String ?? "")
    },
    "session-share": { params in
      SessionShareController(workspaceId: params["workspaceId"] as? String ?? "", sessionId: params["sessionId"] as? String ?? "")
    },
    "agent-error": { params in AgentErrorController(params: params) },
    "edit-message": { params in
      EditMessageController(sessionId: params["sessionId"] as! String, entryId: params["entryId"] as! String)
    },
    "message-details": { params in
      let entryId = params["entryId"] as! String
      let entries = try! JSONDecoder().decode([ChatEntry].self, from: Data((params["entriesJSON"] as! String).utf8))
      return MessageDetailsController(entryId: entryId, entry: entries.first { $0.id == entryId })
    },
    "session-item-detail": { params in
      ItemDetailController(sessionId: params["sessionId"] as! String, entryId: params["entryId"] as! String,
                           itemIds: params["itemIds"] as! [String], generation: params["generation"] as! Int)
    },
    "message-share": { params in MessageShareController(contentJSON: params["contentJSON"] as? String ?? "") },
    "notification-settings": { _ in NotificationSettingsController() },
    "onboarding": { _ in OnboardingController() },
    "mention-picker": { params in MentionPickerController.page(params) },
    "create-session": { params in CreateSessionHostController(params: decode(CreateSessionHostParams.self, params) ?? CreateSessionHostParams()) },
  ]

  private static func picker(_ params: [String: Any]) -> UIViewController {
    let options = (params["options"] as? [[String: Any]] ?? []).map {
      (id: $0["id"] as? String ?? "", title: $0["title"] as? String ?? "", subtitle: $0["subtitle"] as? String ?? "")
    }
    let owner = WeakPageReference()
    let picker = CreateChoiceController(
      title: params["title"] as? String ?? String(localized: "picker.title", bundle: .lody), header: params["header"] as? String ?? "",
      placeholder: params["placeholder"] as? String ?? String(localized: "picker.empty", bundle: .lody), options: options,
      selected: params["selectedId"] as? String, onPick: { id in LodyShell.shared.finish(from: owner.value, value: id) }
    )
    owner.value = picker
    return picker
  }

  private static func decode<Value: Decodable>(_ type: Value.Type, _ params: [String: Any]) -> Value? {
    guard let data = try? JSONSerialization.data(withJSONObject: params) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  static func make(_ id: String, params: String?) -> UIViewController? {
    let object = params.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
    let parameters = object ?? [:]
    return factories[id]?(parameters) ?? debugSceneFactory?(id, parameters)
  }
}

private final class WeakPageReference {
  weak var value: UIViewController?
}
