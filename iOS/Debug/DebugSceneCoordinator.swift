import LodyCore
import UIKit

@MainActor
enum DebugSceneCoordinator {
  static func start(in window: UIWindow) {
    precondition(LodyUIVerify.enabled)
    if LodyUIVerify.home {
      do { try HomeFixture.prepare() }
      catch { preconditionFailure("Invalid offline fixture: \(error)") }
    }
    let root: UIViewController = LodyUIVerify.has("--ui-verify-home") ? HomeController() : DebugViewController()
    LodyShell.shared.start(in: window, content: root, title: root is DebugViewController ? "Debug" : "")
    let ready = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    ready.isAccessibilityElement = true
    ready.accessibilityIdentifier = "ui-verify-ready"
    ready.accessibilityLabel = "Offline fixtures ready"
    window.addSubview(ready)
  }

  static func open(_ params: [String: String]) {
    guard LodyUIVerify.enabled || _isDebugAssertConfiguration() else { return }
    guard let scenario = params["verifyCase"] else {
      LodyShell.shared.pushRoot(DebugViewController(), title: "Debug")
      return
    }
    if scenario == "home-layout-alert" {
      let alert = UIAlertController(title: "Layout verification", message: nil, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      LodyShell.shared.presenter?.present(alert, animated: true)
      return
    }
    if scenario == "home-file-preview" {
      guard let home = HomeController.current,
            let content = PageFactory.make("file-diff-preview", params: "{}") else {
        preconditionFailure("Home file preview requires an open offline Home session")
      }
      LodyShell.shared.presentDetail(content, title: String(localized: "diff.title", bundle: .lody), from: home, push: true, detents: [1])
      return
    }
    let content: UIViewController
    var id = scenario
    var fields: [String: Any] = [:]
    let variants = ["session-preview-": "session-preview", "activity-preview-": "activity-preview",
      "settings-baseline-": "settings-baseline", "edit-message-": "edit-message-preview"]
    for (prefix, page) in variants where scenario.hasPrefix(prefix) && scenario != page {
      id = page; fields["scenario"] = String(scenario.dropFirst(prefix.count)); break
    }
    if ["send-queue", "send-guide", "send-interrupt", "send-scroll-guide", "send-scroll-queue", "send-scroll-normal"].contains(scenario) {
      id = "send-preview"
      fields["queue"] = scenario != "send-scroll-normal"
      fields["steer"] = scenario != "send-interrupt"
      fields["longContext"] = scenario.hasPrefix("send-scroll-")
      fields["queuedMessageBehavior"] = scenario.hasSuffix("guide") ? "guide" : "queue"
    }
    let aliases = ["permission-waiting": "permission-preview",
      "appearance-preview": "settings", "diagnostics-settings-preview": "settings",
      "preferences-preview": "preferences", "queued-message-behavior-preview": "preferences",
      "project-preview-empty": "project-preview", "project-preview-offline": "project-preview"]
    id = aliases[id] ?? id
    if scenario == "permission-waiting" { fields["waiting"] = true }
    if scenario == "item-detail-preview" { fields["scenario"] = "paging" }
    if scenario == "project-preview-empty" || scenario == "project-preview-offline" { fields["projectId"] = "preview-empty" }
    if scenario == "project-preview-offline" { fields["offline"] = true }
    if ["create-parity", "create-recovery", "create-scope", "model-memory", "project-picker-preview"].contains(scenario) {
      content = CreateSessionPreviewController(scenario: scenario == "project-picker-preview" ? "create-parity" : scenario)
    } else {
      guard let page = PageFactory.make(id, params: SessionController.json(fields)) else {
        preconditionFailure("Missing verification scene: \(scenario)")
      }
      content = page
    }
    // Home hosts sessions in a navigation stack. A sheet host shrinks under the next sheet,
    // which moves a late repeated touch off the link it would otherwise tap again.
    if scenario == "session-preview-tasks" {
      LodyShell.shared.pushRoot(content, title: "")
      return
    }
    let onboarding = content is OnboardingController
    let regular = LodyShell.shared.presenter?.traitCollection.horizontalSizeClass == .regular
    LodyShell.shared.present(content, title: content.title ?? "", detents: [1], grabber: !onboarding,
      dismissible: !onboarding, style: regular ? "formSheet" : "pageSheet",
      headerShown: !onboarding && !(content is CreateSessionHostController))
  }
}
