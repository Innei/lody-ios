import ExpoModulesCore
import UIKit

final class LodyCreateSessionView: ExpoView {
  let onSubmit = EventDispatcher()
  let onPreferences = EventDispatcher()
  let onSelection = EventDispatcher()
  let onRelayReady = EventDispatcher()
  let onMentionBrowse = EventDispatcher()
  let onOpenCreated = EventDispatcher()
  let onCancel = EventDispatcher()
  private let input: LodyComposerView
  private let controller: CreateSessionController
  private let navigation: UINavigationController
  private let recovery = ShareRecovery()
  private var hasCreated = false
  var composerRelay = true { didSet { input.composerRelay = composerRelay } }
  required init(appContext: AppContext? = nil) {
    input = LodyComposerView(appContext: appContext)
    controller = CreateSessionController(composer: input.composer, host: input)
    navigation = UINavigationController(rootViewController: controller)
    super.init(appContext: appContext)
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.onCancel([:]) })
    input.composerRelay = true
    input.onSubmitPayload = { [weak self] in self?.controller.submit($0) }
    input.onRelayCompletion = { [weak self] in self?.onRelayReady([:]) }
    input.onMeasuredHeight = { [weak self] in self?.controller.setComposerHeight($0) }
    controller.onSubmit = { [weak self] in self?.onSubmit(["json": createJSON($0)]) }
    controller.onRejected = { [weak self] in
      self?.input.restoreDraft(token: 0)
      self?.input.composer.restoreRejectedDraft()
    }
    controller.onPreferences = { [weak self] in self?.onPreferences(["json": createJSON($0)]) }
    controller.onSelection = { [weak self] project in
      guard let self else { return }
      var source = self.controller.form.agent ?? [:]
      source["agentConfigId"] = source["id"]
      source["workspaceId"] = self.controller.form.workspaceID
      source["projectId"] = project
      self.onSelection(["projectId": project, "source": createJSON(source)])
    }
    input.composer.onMentionBrowse = { [weak self] in self?.onMentionBrowse($0) }
    clipsToBounds = true
  }
  func configure(_ json: String) {
    guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
    controller.configure(value)
    updateRecovery()
  }
  func setBusy(_ value: Bool) { controller.busy = value }
  func setOpenCreated(_ value: Bool) {
    hasCreated = value
    controller.submissionLocked = value
    controller.recoveryTitle = LodyStrings.text("native.create.openCreated")
    controller.onRecovery = value ? { [weak self] in self?.onOpenCreated([:]) } : nil
    controller.render()
    if !value { updateRecovery() }
  }
  private func updateRecovery() {
    guard !hasCreated else { return }
    let pending = ShareStore.pending(user: controller.form.userID, workspace: controller.form.workspaceID)
    controller.recoveryTitle = nil
    controller.onRecovery = pending.isEmpty ? nil : { [weak self] in
      guard let self else { return }
      self.recovery.present(on: self.controller) { [weak self] result in
        self?.controller.notice = ShareRecovery.notice(result)
        self?.updateRecovery()
      }
    }
    controller.render()
  }
  func restore(_ token: Int) { input.restoreDraft(token: token) }
  func mentions(_ json: String) { input.composer.setMentionItems(json) }
  func mentionResult(_ json: String) { input.composer.setMentionResult(json) }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil, navigation.parent == nil, let owner = reactViewController() {
      // RNSScreenStack requires every pushed child to be an RNSScreen. Own the
      // shared UIKit picker stack instead of pushing into that external stack.
      owner.addChild(navigation); addSubview(navigation.view); navigation.didMove(toParent: owner)
      navigation.view.frame = bounds
    } else if window == nil, navigation.parent != nil {
      recovery.cancel()
      navigation.willMove(toParent: nil); navigation.view.removeFromSuperview(); navigation.removeFromParent()
    }
  }
  override func layoutSubviews() { super.layoutSubviews(); navigation.viewIfLoaded?.frame = bounds }
}
