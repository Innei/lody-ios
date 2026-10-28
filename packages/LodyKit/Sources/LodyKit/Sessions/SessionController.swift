import LodyCore
import UIKit

@MainActor
class SessionController: UIViewController {
  typealias BrowserRequest = @MainActor (SessionListState, RuntimeContract.SessionPreviewParamsAction) async throws -> RuntimeContract.SessionPreviewResult
  let chat = LodyChatView(frame: .zero)
  let source: SessionSource
  let sessionId: String
  var environment: SessionSendEnvironment
  private let feedService: SessionFeedService
  private let findQuery: String
  private lazy var actions = SessionActions(source: source)
  private(set) var feed: SessionFeed?
  lazy var composerModel = SessionComposerModel(choice: initialChoice, service: environment.composer)
  lazy var control = SessionControl(request: environment.control)
  var sender: SessionSender?
  let planDecision = SessionDecision(.plan)
  let errorRetry = SessionDecision(.retry)
  let itemDetailService: ItemDetailService
  let permissionService: PermissionService
  var permissionGate = SessionPermissionGate()
  weak var subagentPage: SubagentTaskController?
  var simulator: SessionSimulator?
  var openingSimulator = false
  var browserBusy = false
  let requestBrowserPreview: BrowserRequest
  let simulatorService: SimulatorService?
  let pullRequestPage: @MainActor (SessionPullRequest, SessionListState) -> PullRequestController
  weak var processPage: ProcessController?
  var permissionPage: PermissionController?
  var permissionScope: (userId: String, workspaceId: String)?
  var openingFile = false
  var mentions: MentionCatalogStore?
  var mentionSequence = 0
  var editable = ""
  var editCheck = ""
  var quotaEntry = "pending"
  var rendered: [String: String] = [:]
  private let initialChoice: ModelChoice?
  private var observers: [NSObjectProtocol] = []
  private var findToken = 0
  private var listed = false
  private var moreItem: UIBarButtonItem?
  private var renderedEntries: String?

  init(sessionId: String, findQuery: String = "", choice: ModelChoice? = nil, source: SessionSource = .live,
       feed: SessionFeedService = .live, environment: SessionSendEnvironment = .live, permission: PermissionService = .live,
       itemDetail: ItemDetailService? = nil, simulator: SimulatorService? = nil,
       pullRequest: @escaping @MainActor (SessionPullRequest, SessionListState) -> PullRequestController = SessionController.livePullRequest,
       browser: BrowserRequest? = nil) {
    requestBrowserPreview = browser ?? { state, action in
      guard let runtime = DataRuntime.current, runtime.workspace == state.workspaceId, runtime.userId == state.userId else { throw OutboxError.scopeExpired }
      return try await runtime.perform(RuntimeContract.Calls.SessionPreview.self, .init(sessionId: sessionId, userId: state.userId, action: action))
    }
    self.sessionId = sessionId
    self.findQuery = findQuery
    self.source = source
    self.environment = environment
    permissionService = permission
    itemDetailService = itemDetail ?? .live(sessionId: sessionId)
    simulatorService = simulator
    pullRequestPage = pullRequest
    initialChoice = choice
    feedService = feed
    super.init(nibName: nil, bundle: nil)
  }

  convenience init(params: [String: Any]) {
    let keys = ["modelId", "effort", "modeId"]
    var choice: ModelChoice?
    if keys.contains(where: { params[$0] is String }) {
      choice = ModelChoice(modelId: params["modelId"] as? String, effort: params["effort"] as? String, modeId: params["modeId"] as? String)
    }
    let sessionId: String
    if let id = params["sessionId"] as? String { sessionId = id }
    else { sessionId = (params["session"] as! [String: Any])["id"] as! String }
    self.init(sessionId: sessionId, findQuery: params["findQuery"] as? String ?? "", choice: choice)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    feed?.finish()
    simulator?.finish()
    if sender != nil { environment.foreground(sessionId, false) }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  var queuedMessageBehavior: String { LodyPreferences.queuedMessageBehavior }
  var persistsDraft: Bool { true }
  var composerPreview: [String: Any]? { makeComposerPreview() }
  func adjustComposer(_ state: inout [String: Any]) {}

  // The chat binds its title and scroll edges to its nearest controller; the shell page shows this item.
  override var navigationItem: UINavigationItem { parent?.navigationItem ?? super.navigationItem }

  override func viewDidLoad() {
    super.viewDidLoad()
    chat.frame = view.bounds
    chat.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(chat)
    chat.imageSharingEnabled = false
    wireEvents()
    find(query: findQuery, keyboard: false)
    wireSendEvents()
    wireDecisionEvents()
    wireRouteEvents()
    chat.onPreview = { [weak self] body in
      if let action = body["action"] as? String { self?.contextAction(action) }
    }
    wireMentionEvents()
    observers = (source.changes + [UIApplication.didBecomeActiveNotification, .lodyPreferencesDidChange]).map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        let activated = note.name == UIApplication.didBecomeActiveNotification
        MainActor.assumeIsolated {
          self?.render()
          if activated { self?.markViewed() }
        }
      }
    }
    render()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    NotificationCenter.default.post(name: LodyScrollEdges.ownerChanged, object: self)
    let slug = source.state.workspace?.slug ?? ""
    PushNotifications.shared.visibleRoute = slug.isEmpty ? "" : "/\(slug)/sessions/\(sessionId)"
    markViewed()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    renderPermission()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    PushNotifications.shared.visibleRoute = ""
    if SettingsPage.leaving(self) {
      permissionPage?.update(nil, ready: true)
      processPage?.navigationController?.presentingViewController?.dismiss(animated: false)
    }
  }

  func render() {
    guard isViewLoaded else { return }
    let state = source.state
    guard let session = state.catalog.session(sessionId) else {
      permissionPage?.update(nil, ready: true)
      if listed, !state.loading { LodyShell.shared.close(from: self) }
      return
    }
    listed = true
    prepareSimulator(state, session)
    startFeed(state)
    chat.setAttachmentContext(Self.json(["workspaceId": state.workspaceId, "sessionId": sessionId]))
    let machine = state.catalog.machineNames[session.machineId] ?? ""
    let machineState = state.presence.status(of: session.machineId)
    chat.setNavigationTitle(session.title)
    chat.setNavigationSubtitle(projectName(session, catalog: state.catalog))
    chat.setNavigationMachine(machine.isEmpty ? String(localized: "session.title.machine", bundle: .lody) : machine)
    chat.setNavigationMachineState(machineState)
    chat.setNavigationBranch(session.branchName ?? "")
    chat.setTitleMenu(titleMenu(session, machine: machine, machineState: machineState))
    chat.mentionRepository = session.projectId.hasPrefix("github:") ? String(session.projectId.dropFirst(7)) : ""
    renderMentions(state, session)
    renderFeed(session)
    updateMoreMenu(session)
  }

  private func startFeed(_ state: SessionListState) {
    guard feed == nil, !state.userId.isEmpty, !state.workspaceId.isEmpty else { return }
    let feed = SessionFeed(sessionId: sessionId, userId: state.userId, workspaceId: state.workspaceId, service: feedService)
    feed.changed = { [weak self] in
      guard let self, let session = self.source.state.catalog.session(self.sessionId) else { return }
      self.renderFeed(session)
    }
    self.feed = feed
    startSender(state)
    feed.start()
  }

  private func renderFeed(_ session: SessionItem) {
    let state = feed?.state ?? SessionFeedState()
    renderComposer(session, state)
    renderPermission()
    chat.setEmptyText(String(localized: String.LocalizationValue(state.status == "live" ? "chat.empty.prompt" : "chat.empty.loading"), bundle: .lody))
    guard state.entriesJSON != renderedEntries else { return }
    renderedEntries = state.entriesJSON
    processPage?.update(state.entriesJSON)
    updateDetails(state.entriesJSON)
    chat.setEntries(state.entriesJSON)
    chat.scheduleUpdate()
  }

  private func projectName(_ session: SessionItem, catalog: SessionCatalog) -> String {
    if SessionRows.isChat(session.projectId) { return String(localized: "inbox.section.chat", bundle: .lody) }
    return catalog.projects.first { $0.id == session.projectId }?.name ?? ""
  }

  private func titleMenu(_ session: SessionItem, machine: String, machineState: String) -> String {
    var items: [[String: Any]] = []
    if browsable {
      items.append([
        "id": "files", "title": String(localized: "session.action.projectFiles", bundle: .lody),
        "subtitle": projectName(session, catalog: source.state.catalog), "symbol": "folder",
      ])
    }
    if let branch = session.branchName {
      items.append([
        "id": "branch", "title": String(localized: "session.title.copyBranch", bundle: .lody), "subtitle": branch,
        "symbol": "arrow.triangle.branch",
      ])
    }
    if !machine.isEmpty {
      items.append([
        "id": "machine", "title": String(localized: "session.title.machine", bundle: .lody),
        "subtitle": "\(machine) · \(String(localized: String.LocalizationValue("devices." + machineState), bundle: .lody))", "symbol": "desktopcomputer",
      ])
    }
    items.append(["id": "rename", "title": String(localized: "session.action.rename", bundle: .lody), "symbol": "pencil", "group": 1])
    guard let data = try? JSONSerialization.data(withJSONObject: items) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  private func updateMoreMenu(_ session: SessionItem) {
    let deleting = SessionActions.isDeleting(source.state.workspaceId, sessionId)
    let more = moreItem ?? UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: nil)
    more.accessibilityLabel = String(localized: "common.more", bundle: .lody)
    var changes: [UIMenuElement] = []
    if reviewable {
      changes.append(UIAction(title: String(localized: "workspaceChanges.title", bundle: .lody), image: UIImage(systemName: "plus.forwardslash.minus")) {
        [weak self] _ in self?.openWorkspaceChanges()
      })
    }
    more.menu = UIMenu(children: changes + simulatorMenu() + [
      UIAction(title: String(localized: "session.action.find", bundle: .lody), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
        self?.find(query: "", keyboard: true)
      },
      UIAction(title: String(localized: "session.action.share", bundle: .lody), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
        self?.perform("share")
      },
      UIAction(
        title: String(localized: String.LocalizationValue(session.archived ? "session.action.unarchive" : "session.action.archive"), bundle: .lody),
        image: UIImage(systemName: session.archived ? "tray.and.arrow.up" : "archivebox")
      ) { [weak self] _ in self?.perform("archive") },
      UIMenu(options: .displayInline, children: [
        UIAction(
          title: String(localized: String.LocalizationValue(deleting ? "session.delete.pending" : "session.action.delete"), bundle: .lody),
          image: UIImage(systemName: "trash"), attributes: deleting ? [.destructive, .disabled] : .destructive
        ) { [weak self] _ in self?.perform("delete") },
      ]),
    ])
    moreItem = more
    let header = LodyNavigationHeader.of(navigationItem)
    let items = [pullRequestItem(session), more].compactMap { $0 }
    if header.rightItems != items { header.rightItems = items }
  }

  private func wireEvents() {
    chat.onReconnect = { [weak self] _ in self?.feed?.reconnect() }
    chat.onTitleMenu = { [weak self] body in self?.titleMenuSelected(body["id"] as? String ?? "") }
  }

  private func titleMenuSelected(_ id: String) {
    switch id {
    case "branch":
      guard let branch = source.state.catalog.session(sessionId)?.branchName else { return }
      UIPasteboard.general.string = branch
      LodyToastOverlay.shared.show(message: String(localized: "session.title.branchCopied", bundle: .lody), kind: "info")
    case "rename":
      perform("rename")
    case "files":
      guard let session = source.state.catalog.session(sessionId) else { return }
      let name = projectName(session, catalog: source.state.catalog)
      openProjectFiles(title: name.isEmpty ? String(localized: "session.action.projectFiles", bundle: .lody) : name)
    default:
      break
    }
  }

  private func perform(_ action: String) {
    actions.perform(action, row: sessionId, from: self)
  }

  func find(query: String, keyboard: Bool) {
    guard keyboard || !query.isEmpty else { return }
    findToken += 1
    chat.setFindRequest(Self.json(["token": findToken, "query": query, "keyboard": keyboard, "open": true]))
  }

  private func markViewed() {
    guard UIApplication.shared.applicationState == .active, view.window != nil else { return }
    let state = source.state
    SessionSource.markViewed(
      userId: state.userId, workspaceId: state.workspaceId, sessionId: sessionId,
      at: state.catalog.session(sessionId)?.lastMessageAt
    )
  }

  static func json(_ object: [String: Any]) -> String {
    (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }
}
