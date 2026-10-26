import UIKit

@MainActor
enum LodyNativePages {
  private static let factories: [String: ([String: Any]) -> UIViewController] = [
    "appearance-settings": { _ in AppearanceController() },
    "app-icon": { _ in AppIconController() },
    "about": { _ in AboutController() },
    "preferences": { _ in PreferencesController() },
    "quick-reply-editor": { params in QuickReplyEditorController(item: QuickReply(params["item"])) },
    "ai-usage": { _ in AIUsageController() },
    "ai-usage-preview": { _ in AIUsagePreviewController() },
    "project-visibility": { _ in ProjectVisibilityController() },
    "project-visibility-preview": { _ in ProjectVisibilityPreviewController() },
    "github-settings": { _ in GitHubSettingsController() },
    "github-settings-preview": { _ in GitHubSettingsPreviewController() },
    "prompt-shortcuts": { _ in PromptShortcutsController() },
    "prompt-shortcuts-preview": { _ in PromptShortcutsPreviewController() },
    "agent-roles": { _ in AgentRolesController() },
    "agent-roles-preview": { _ in AgentRolesPreviewController() },
    "settings": { _ in SettingsController() },
    "settings-baseline": { params in SettingsBaselineController(scenario: params["scenario"] as? String ?? "live") },
    "memory-settings": { params in MemorySettingsController(scope: .live(params)) },
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
    "published-shares": { params in PublishedSharesController(scope: .live(params)) },
    "published-shares-preview": { _ in PublishedSharesPreviewController() },
    "published-shares-empty": { _ in PublishedSharesPreviewController(state: "empty") },
    "published-shares-denied": { _ in PublishedSharesPreviewController(state: "denied") },
    "published-shares-readonly": { _ in PublishedSharesPreviewController(state: "readonly") },
    "published-shares-readback-denied": { _ in PublishedSharesPreviewController(state: "readback-denied") },
    "remote-settings": { params in RemoteSettingsController(kind: params["kind"] as? String ?? "machine", scope: .live(params)) },
    "settings-preview": { _ in SettingsPreviewController() },
    "mcp-settings-preview": { _ in RemoteSettingsPreviews.mcp() },
    "machine-settings-preview": { _ in RemoteSettingsPreviews.machine() },
    "remote-setting-editor-preview": { params in RemoteSettingsPreviews.editor(params) },
  ]

  static func make(_ id: String, params: String?) -> UIViewController? {
    let object = params.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
    return factories[id]?(object ?? [:])
  }
}
