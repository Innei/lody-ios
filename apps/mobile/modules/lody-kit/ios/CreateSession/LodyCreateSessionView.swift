import ExpoModulesCore
import UIKit

final class LodyCreateSessionView: ExpoView {
  let onRequest = EventDispatcher()
  let onPrefs = EventDispatcher()
  let onSelection = EventDispatcher()
  let onSubmit = EventDispatcher()
  let onRelayReady = EventDispatcher()
  let onMentionBrowse = EventDispatcher()
  let onCancel = EventDispatcher()

  private let input: LodyComposerView
  private let controller: CreateSessionController
  private let navigation: UINavigationController
  private var pending: [String: CheckedContinuation<String?, Error>] = [:]
  private var configured = false
  private var persistShare = false

  required init(appContext: AppContext? = nil) {
    input = LodyComposerView(appContext: appContext)
    controller = CreateSessionController(composer: input.composer, host: input)
    navigation = UINavigationController(rootViewController: controller)
    super.init(appContext: appContext)
    input.scrollEdge = true
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigation.navigationBar.standardAppearance = appearance
    navigation.navigationBar.scrollEdgeAppearance = appearance
    navigation.navigationBar.compactAppearance = appearance
    navigation.view.backgroundColor = .clear

    input.forwarded = { [weak self] name, body in
      guard let self else { return }
      switch name {
      case "send": self.controller.submit(body)
      case "relayReady": self.onRelayReady([:])
      case "contentHeight": self.controller.setComposerHeight(body["height"] as? CGFloat ?? 64)
      case "mentionBrowse": self.onMentionBrowse(body)
      case "optionChange": self.controller.composerOptionChanged(body)
      default: break
      }
    }
    controller.restoreDraft = { [weak self] token in self?.input.restoreDraft(token: token) }
    controller.showMessage = { LodyToastOverlay.shared.show(message: $0, kind: "error") }
    controller.onCancel = { [weak self] in self?.onCancel([:]) }
    controller.onPrefs = { [weak self] prefs in
      guard let self else { return }
      if self.persistShare { try? ShareStore.writePrefs(prefs) }
      self.onPrefs(["json": CreateJSON.encode(prefs)])
    }
    controller.onSelection = { [weak self] form in
      let page = form.current
      self?.onSelection([
        "workspaceId": form.workspaceId, "projectId": page.chat ? "" : page.projectId,
        "machineId": page.machine?.id ?? "", "agentConfigId": page.agent?.id ?? "",
        "cliType": page.agent?.cliType ?? "", "agentType": page.agent?.agentType ?? "",
      ])
    }
    controller.onSubmit = { [weak self] draft, payload in
      guard let draft else { return }
      self?.onSubmit(["draft": CreateJSON.encode(draft), "payload": payload])
    }
    controller.loadOptions = { [weak self] projectId in
      guard let self else { throw CancellationError() }
      let value = try await self.request("options", ["projectId": projectId ?? ""])
      guard let json = value, let options = CreateJSON.decode(CreationOptions.self, json) else {
        throw CocoaError(.coderReadCorrupt)
      }
      if self.persistShare { try? ShareStore.writeOptions(options, target: projectId ?? CreateLogic.chatTarget) }
      return options
    }
    controller.loadRepositories = { [weak self] in
      guard let self else { throw CancellationError() }
      let value = try await self.request("repositories", [:])
      return CreateJSON.decode([CreateProject].self, value ?? "") ?? []
    }
    controller.browseProject = { [weak self] in
      guard let self, let json = try? await self.request("browse", [:]) else { return nil }
      return CreateJSON.decode(CreateProject.self, json)
    }
  }

  private func request(_ kind: String, _ body: [String: Any]) async throws -> String? {
    let id = UUID().uuidString
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      onRequest(body.merging(["id": id, "kind": kind]) { $1 })
    }
  }

  func respond(_ json: String) {
    let responses = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]) ?? []
    for body in responses {
      guard let id = body["id"] as? String, let continuation = pending.removeValue(forKey: id) else { continue }
      if let error = body["error"] as? String {
        continuation.resume(throwing: NSError(domain: "LodyCreateSession", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
      } else {
        continuation.resume(returning: body["value"] as? String)
      }
    }
  }

  func configure(_ json: String) {
    guard !configured, let config = CreateJSON.decode(CreateSessionConfig.self, json) else { return }
    configured = true
    persistShare = config.persistShare
    controller.form = CreateSessionForm(
      userId: config.userId, workspaceId: config.workspaceId, projects: config.projects,
      machineNames: config.machineNames, prefs: config.prefs)
    controller.form.open(projectId: config.projectId, context: config.context)
    if !config.initialText.isEmpty { input.composer.setInitialDraft(config.initialText) }
    if !config.initialAttachments.isEmpty { input.composer.setInitialAttachments(config.initialAttachments) }
    if controller.isViewLoaded {
      controller.render()
      controller.load(chat: false)
      if !controller.form.locked { controller.load(chat: true) }
    }
  }

  func setComposerRelay(_ value: Bool) { input.composerRelay = value }
  func setSendHandoff(_ value: Bool) { input.composer.sendHandoff = value }
  func restore(_ token: Int) {
    guard token > 0 else { return }
    controller.submissionFailed()
  }
  func setMentionItems(_ json: String) { input.composer.setMentionItems(json) }
  func setMentionResult(_ json: String) { input.composer.setMentionResult(json) }

  private func cancelRequests() {
    let waiting = pending.values
    pending = [:]
    for continuation in waiting { continuation.resume(throwing: CancellationError()) }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { cancelRequests() }
    if window != nil, navigation.parent == nil, let owner = reactViewController() {
      // RNSScreenStack accepts only RNSScreen children; the form owns its own stack.
      owner.addChild(navigation)
      addSubview(navigation.view)
      navigation.view.frame = bounds
      navigation.didMove(toParent: owner)
    } else if window == nil, navigation.parent != nil, input.relayPayload == nil {
      navigation.willMove(toParent: nil)
      navigation.view.removeFromSuperview()
      navigation.removeFromParent()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    navigation.viewIfLoaded?.frame = bounds
  }
}

struct CreateSessionConfig: Decodable {
  var userId: String
  var workspaceId: String
  var projects: [CreateProject]
  var machineNames: [String: String] = [:]
  var prefs: CreatePrefs?
  var projectId: String?
  var context: String?
  var initialText: String = ""
  var initialAttachments: String = ""
  var persistShare = false

  enum CodingKeys: String, CodingKey {
    case userId, workspaceId, projects, machineNames, prefs, projectId, context, initialText, initialAttachments, persistShare
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    userId = try values.decode(String.self, forKey: .userId)
    workspaceId = try values.decode(String.self, forKey: .workspaceId)
    projects = try values.decode([CreateProject].self, forKey: .projects)
    machineNames = try values.decodeIfPresent([String: String].self, forKey: .machineNames) ?? [:]
    prefs = try values.decodeIfPresent(CreatePrefs.self, forKey: .prefs)
    projectId = try values.decodeIfPresent(String.self, forKey: .projectId)
    context = try values.decodeIfPresent(String.self, forKey: .context)
    initialText = try values.decodeIfPresent(String.self, forKey: .initialText) ?? ""
    initialAttachments = try values.decodeIfPresent(String.self, forKey: .initialAttachments) ?? ""
    persistShare = try values.decodeIfPresent(Bool.self, forKey: .persistShare) ?? false
  }
}
