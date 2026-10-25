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
  ]

  static func make(_ id: String, params: String?) -> UIViewController? {
    let object = params.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
    return factories[id]?(object ?? [:])
  }
}
