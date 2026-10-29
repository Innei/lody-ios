import LodyCore
import UIKit

struct CreateSessionHostParams: Decodable {
  var userId = ""
  var workspaceId = ""
  var projects: [CreateProject] = []
  var machineNames: [String: String] = [:]
  var projectId: String?
  var context: String?
  var initialText: String?
  var initialAttachmentsJSON: String?
  var sendHandoff: Bool?
  var relay: Bool?

  init() {}

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    userId = try values.decodeIfPresent(String.self, forKey: .userId) ?? ""
    workspaceId = try values.decodeIfPresent(String.self, forKey: .workspaceId) ?? ""
    projects = try values.decodeIfPresent([CreateProject].self, forKey: .projects) ?? []
    machineNames = try values.decodeIfPresent([String: String].self, forKey: .machineNames) ?? [:]
    projectId = try values.decodeIfPresent(String.self, forKey: .projectId)
    context = try values.decodeIfPresent(String.self, forKey: .context)
    initialText = try values.decodeIfPresent(String.self, forKey: .initialText)
    initialAttachmentsJSON = try values.decodeIfPresent(String.self, forKey: .initialAttachmentsJSON)
    sendHandoff = try values.decodeIfPresent(Bool.self, forKey: .sendHandoff)
    relay = try values.decodeIfPresent(Bool.self, forKey: .relay)
  }

  private enum CodingKeys: String, CodingKey {
    case userId, workspaceId, projects, machineNames, projectId, context, initialText, initialAttachmentsJSON, sendHandoff, relay
  }
}

@MainActor
class CreateSessionHostController: UIViewController {
  private let params: CreateSessionHostParams
  private let service: CreateSessionService
  private let input = LodyComposerView(frame: .zero)
  private let controller: CreateSessionController
  private let navigation: UINavigationController
  private var mentions: MentionCatalogStore?
  private var observers: [NSObjectProtocol] = []
  private var refreshKey = ""
  private var created: Any?
  private var opening = false
  var onCreated: (@MainActor ([String: Any]) async throws -> Void)?

  init(params: CreateSessionHostParams, service: CreateSessionService = .live) {
    self.params = params
    self.service = service
    controller = CreateSessionController(composer: input.composer, host: input)
    navigation = UINavigationController(rootViewController: controller)
    super.init(nibName: nil, bundle: nil)
    title = String(localized: "create.title", bundle: .lody)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    input.scrollEdge = true
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigation.navigationBar.standardAppearance = appearance
    navigation.navigationBar.scrollEdgeAppearance = appearance
    navigation.navigationBar.compactAppearance = appearance
    navigation.view.backgroundColor = .clear
    input.composerRelay = relays
    input.composer.sendHandoff = params.sendHandoff ?? true
    wire()
    Task {
      await configure()
      embedForm()
    }
  }

  // The form loads its options when its view loads, so it is embedded only once prefs are in place.
  private func embedForm() {
    addChild(navigation)
    navigation.view.frame = view.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(navigation.view)
    navigation.didMove(toParent: self)
  }

  var relays: Bool { params.relay == true && params.sendHandoff != false }

  private func wire() {
    input.forwarded = { [weak self] name, body in
      guard let self else { return }
      switch name {
      case "send": controller.submit(body)
      case "relayReady": relayReady()
      case "contentHeight": controller.setComposerHeight(body["height"] as? CGFloat ?? 64)
      case "mentionBrowse": browseMentions(body)
      case "optionChange": controller.composerOptionChanged(body)
      default: break
      }
    }
    controller.restoreDraft = { [weak self] token in self?.input.restoreDraft(token: token) }
    controller.showMessage = { LodyToastOverlay.shared.show(message: $0, kind: "error") }
    controller.onCancel = { [weak self] in self?.close() }
    let prefsKey = CreateSessionService.prefsKey(userId: params.userId, workspaceId: params.workspaceId)
    controller.onPrefs = { [weak self] prefs in
      guard let self else { return }
      if service.persistShare { try? ShareStore.writePrefs(prefs) }
      service.writePrefs(prefsKey, prefs)
    }
    controller.onSelection = { [weak self] form in self?.selectionChanged(form) }
    controller.onSubmit = { [weak self] draft, payload in
      guard let draft else { return }
      self?.submit(draft, payload)
    }
    let workspaceId = params.workspaceId
    controller.loadOptions = { [weak self] projectId in
      guard let self else { throw CancellationError() }
      let options = try await service.options(workspaceId, projectId)
      if service.persistShare { try? ShareStore.writeOptions(options, target: projectId ?? CreateLogic.chatTarget) }
      return options
    }
    controller.loadRepositories = { [weak self] in
      guard let self else { throw CancellationError() }
      return try await service.repositories(workspaceId).compactMap(CreateSessionService.githubProject)
    }
    controller.loadBranches = { [weak self] repo, page in
      guard let self else { throw CancellationError() }
      return try await service.branches(workspaceId, repo, page)
    }
    controller.onBranches = { [weak self, params] repo, branches in
      guard self?.service.persistShare == true else { return }
      try? ShareStore.writeBranches(branches, repo: repo, userId: params.userId, workspaceId: params.workspaceId)
    }
    controller.browseProject = { await DirectoryController.browse(workspaceId: workspaceId) }
  }

  private func configure() async {
    let prefs = await service.readPrefs(CreateSessionService.prefsKey(userId: params.userId, workspaceId: params.workspaceId))
    controller.form = CreateSessionForm(
      userId: params.userId, workspaceId: params.workspaceId, projects: params.projects,
      machineNames: params.machineNames, prefs: prefs)
    controller.form.open(projectId: params.projectId, context: params.context)
    if let text = params.initialText, !text.isEmpty { input.composer.setInitialDraft(text) }
    if let attachments = params.initialAttachmentsJSON, !attachments.isEmpty { input.composer.setInitialAttachments(attachments) }
    refreshKey = currentRefreshKey()
    for name in refreshNotifications {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshIfNeeded() }
      })
    }
  }

  var refreshNotifications: [Notification.Name] { [.lodyCatalogDidChange] }

  func currentRefreshKey() -> String {
    let state = (try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.json.utf8))) as? [String: Any]
    let catalog = (try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.raw.utf8))) as? [String: Any]
    let parts: [Any] = [state?["presence"] ?? NSNull(), catalog?["machineIds"] ?? NSNull(), catalog?["agentUsage"] ?? NSNull()]
    let data = (try? JSONSerialization.data(withJSONObject: parts, options: .sortedKeys)) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  func refreshIfNeeded() {
    guard navigation.parent != nil else { return }
    let next = currentRefreshKey()
    guard next != refreshKey else { return }
    refreshKey = next
    controller.refreshOptions()
  }

  private func selectionChanged(_ form: CreateSessionForm) {
    let page = form.current
    guard let machineId = page.machine?.id, !machineId.isEmpty else {
      mentions = nil
      input.composer.setMentionItems("null")
      return
    }
    let source = MentionSource(
      workspaceId: form.workspaceId, projectId: page.chat ? nil : page.projectId.nilIfEmpty, machineId: machineId,
      agentConfigId: page.agent?.id, cliType: page.agent?.cliType, agentType: page.agent?.agentType
    )
    guard mentions?.source != source else { return }
    let store = MentionCatalogStore(source: source)
    store.changed = { [weak self, weak store] in
      guard let self, let store, mentions === store else { return }
      input.composer.setMentionItems(store.composerItemsJSON())
    }
    mentions = store
    input.composer.setMentionItems(store.composerItemsJSON())
    store.preload()
  }

  private var mentionSequence = 0

  private func browseMentions(_ body: [String: Any]) {
    guard let store = mentions, let category = body["category"] as? String,
          MentionCatalogStore.categories.contains(category) else { return }
    let picker = MentionPickerController(
      category: category, query: body["query"] as? String ?? "", store: store, initial: store.catalog(category)
    ) { [weak self] item in
      guard let self else { return }
      mentionSequence += 1
      let result: [String: Any] = [
        "id": String(mentionSequence), "path": item.path,
        "item": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(item))) ?? NSNull(),
      ]
      let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
      input.composer.setMentionResult(String(decoding: data, as: UTF8.self))
      if let page = parent, let container = page.navigationController { container.popToViewController(page, animated: true) }
    }
    LodyShell.shared.pushNative(
      picker, title: String(localized: String.LocalizationValue("native.chat.mention." + (ChatMentionItem.labels[category] ?? category)), bundle: .lody), from: self
    )
  }

  private func submit(_ draft: CreateSessionDraft, _ payload: [String: Any]) {
    guard !opening else { return controller.submissionFailed() }
    let built = CreateDraftRecord(draft: draft, payload: payload)
    let userId = params.userId, workspaceId = params.workspaceId
    let failed = built.record?.with(phase: "failed", reason: String(localized: "send.error.draftSaveShort", bundle: .lody))
    let task = service.put(userId, workspaceId, built.recordJSON)
    Task { [service] in
      guard (try? await task.value) == nil, let failed else { return }
      _ = try? await service.put(userId, workspaceId, String(decoding: (try? JSONEncoder().encode(failed)) ?? Data(), as: UTF8.self)).value
    }
    created = built.created
    guard relays, input.relayPayload != nil else {
      if let onCreated {
        Task {
          do { try await onCreated(built.created as! [String: Any]); close() }
          catch { controller.submissionFailed(); LodyToastOverlay.shared.show(message: String(localized: "session.toast.openFailed", bundle: .lody), kind: "error") }
        }
      } else { LodyShell.shared.finish(from: self, value: built.created); close() }
      return
    }
    opening = true
    Task {
      do {
        if let onCreated { try await onCreated(built.created as! [String: Any]) }
        else { try await LodyShell.shared.callback(from: self, name: "onCreated", value: built.created ?? NSNull()) }
      } catch {
        guard opening, (error as NSError).localizedDescription != "request_reset" else { return }
        opening = false
        created = nil
        controller.submissionFailed()
        LodyToastOverlay.shared.show(message: String(localized: "session.toast.openFailed", bundle: .lody), kind: "error")
        return
      }
      opening = false
    }
  }

  private func relayReady() {
    guard let created else { return }
    LodyShell.shared.finish(from: self, value: created)
    close()
  }

  private func close() {
    LodyShell.shared.close(from: self)
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
