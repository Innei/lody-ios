import UIKit

@MainActor
enum DebugSceneFactory {
  private static let scenes: [String: ([String: Any]) -> UIViewController] = [
    "debug": { _ in DebugViewController() },
    "pull-request-preview": { params in PullRequestPreviewController(params: params) },
    "files-fixture": { params in
      FilesFixtureController(params: .init(workspaceId: params["workspaceId"] as! String, sessionId: params["sessionId"] as! String,
        relativePath: params["path"] as! String, userId: params["userId"] as! String))
    },
    "file-content-fixture": { params in FileContentFixtureController(params: params) },
    "file-diff-fixture": { params in FileDiffFixtureController(params: params) },
    "ai-usage-preview": { _ in AIUsagePreviewController() },
    "project-visibility-preview": { _ in ProjectVisibilityPreviewController() },
    "github-settings-preview": { _ in GitHubSettingsPreviewController() },
    "prompt-shortcuts-preview": { _ in PromptShortcutsPreviewController() },
    "agent-roles-preview": { _ in AgentRolesPreviewController() },
    "settings-baseline": { params in SettingsBaselineController(scenario: params["scenario"] as? String ?? "live") },
    "archived-sessions-preview": { _ in ArchivedSessionsPreviewController() },
    "permission-sheet-preview": { params in PermissionSheetPreviewController(scenario: params["scenario"] as! String) },
    "permission-preview": { params in PermissionPreviewController(waiting: params["waiting"] as? Bool == true) },
    "session-preview": { params in SessionPreviewController(scenario: params["scenario"] as? String ?? "live") },
    "send-preview": { params in SendPreviewController(params: params) },
    "agent-error-preview": { _ in AgentErrorPreviewController() },
    "memory-preview": { _ in MemoryPreviewController() },
    "memory-states-preview": { _ in MemoryPreviewController(state: "not_installed") },
    "memory-state-catalog_denied": { _ in MemoryPreviewController(state: "catalog_denied") },
    "memory-state-not_installed": { _ in MemoryPreviewController(state: "not_installed") },
    "memory-state-not_running": { _ in MemoryPreviewController(state: "not_running") },
    "memory-state-unsupported": { _ in MemoryPreviewController(state: "unsupported") },
    "memory-state-error": { _ in MemoryPreviewController(state: "error") },
    "memory-state-forbidden": { _ in MemoryPreviewController(state: "forbidden") },
    "memory-state-unknown": { _ in MemoryPreviewController(state: "unknown") },
    "memory-state-cached": { _ in MemoryPreviewController(state: "cached") },
    "memory-state-empty": { _ in MemoryPreviewController(state: "empty") },
    "published-shares-preview": { _ in PublishedSharesPreviewController() },
    "published-shares-empty": { _ in PublishedSharesPreviewController(state: "empty") },
    "published-shares-denied": { _ in PublishedSharesPreviewController(state: "denied") },
    "published-shares-readonly": { _ in PublishedSharesPreviewController(state: "readonly") },
    "published-shares-readback-denied": { _ in PublishedSharesPreviewController(state: "readback-denied") },
    "settings-preview": { _ in SettingsPreviewController() },
    "mcp-settings-preview": { _ in RemoteSettingsPreviews.mcp() },
    "machine-settings-preview": { _ in RemoteSettingsPreviews.machine() },
    "remote-setting-editor-preview": { params in RemoteSettingsPreviews.editor(params) },
    "diagnostics-preview": { _ in DiagnosticsPreviewController() },
    "project-history-preview": { _ in ProjectHistoryPreview.make() },
    "directory-preview": { _ in DirectoryPreviewController() },
    "project-preview": { params in
      ProjectPreviewController(projectId: params["projectId"] as? String ?? "preview-lody", connected: params["offline"] == nil)
    },
    "activity-preview": { params in ActivityPreviewController(scenario: params["scenario"] as? String ?? "live") },
    "session-share-preview": { _ in SessionSharePreviewController() },
    "edit-message-preview": { params in EditMessagePreviewController(scenario: params["scenario"] as? String ?? "retry") },
    "item-detail-preview": { params in ItemDetailPreviewController(scenario: params["scenario"] as! String) },
    "notification-preview": { _ in NotificationPreviewController() },
    "live-activity-preview": { _ in LiveActivityPreviewController() },
    "onboarding-preview": { _ in OnboardingPreviewController() },
    "create-session-preview": { params in CreateSessionPreviewController(scenario: params["scenario"] as? String ?? "create-parity") },
    "file-diff-preview": { _ in FileDiffPreviewController() },
    "workspace-changes-preview": { _ in WorkspaceChangesPreviewController() },
    "file-content-preview": { _ in FileContentPreviewController() },
  ]

  static func make(_ id: String, parameters: [String: Any]) -> UIViewController? {
    scenes[id]?(parameters)
  }
}
