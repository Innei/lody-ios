import UIKit

@MainActor
class SessionController: UIViewController {
  let chat = LodyChatView(appContext: nil)
  let source: SessionSource
  let sessionId: String
  private let feedService: SessionFeedService
  private let findQuery: String
  private lazy var actions = SessionActions(source: source)
  private var feed: SessionFeed?
  private var observers: [NSObjectProtocol] = []
  private var findToken = 0
  private var listed = false
  private var moreItem: UIBarButtonItem?
  private var renderedEntries: String?

  init(sessionId: String, findQuery: String = "", source: SessionSource = .live, feed: SessionFeedService = .live) {
    self.sessionId = sessionId
    self.findQuery = findQuery
    self.source = source
    feedService = feed
    super.init(nibName: nil, bundle: nil)
  }

  convenience init(params: [String: Any]) {
    self.init(sessionId: params["sessionId"] as? String ?? "", findQuery: params["findQuery"] as? String ?? "")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    feed?.finish()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

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
    observers = (source.changes + [UIApplication.didBecomeActiveNotification]).map { name in
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

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    PushNotifications.shared.visibleRoute = ""
  }

  func render() {
    guard isViewLoaded else { return }
    let state = source.state
    guard let session = state.catalog.session(sessionId) else {
      if listed, !state.loading { navigationController?.popViewController(animated: true) }
      return
    }
    listed = true
    startFeed(state)
    chat.setAttachmentContext(Self.json(["workspaceId": state.workspaceId, "sessionId": sessionId]))
    let machine = state.catalog.machineNames[session.machineId] ?? ""
    let machineState = state.presence.status(of: session.machineId)
    chat.setNavigationTitle(session.title)
    chat.setNavigationSubtitle(projectName(session, catalog: state.catalog))
    chat.setNavigationMachine(machine.isEmpty ? LodyStrings.text("session.title.machine") : machine)
    chat.setNavigationMachineState(machineState)
    chat.setNavigationBranch(session.branchName ?? "")
    chat.setTitleMenu(titleMenu(session, machine: machine, machineState: machineState))
    chat.mentionRepository = session.projectId.hasPrefix("github:") ? String(session.projectId.dropFirst(7)) : ""
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
    feed.start()
  }

  private func renderFeed(_ session: SessionItem) {
    let state = feed?.state ?? SessionFeedState()
    let disconnected = ["offline", "failed", "stopped"].contains(state.status)
    var connection = ""
    if !state.overflow, disconnected {
      connection = "paused"
    } else if !state.overflow, state.status != "live" {
      connection = "connecting"
    }
    chat.setComposerState(Self.json([
      "editable": false, "canSend": false, "sending": false, "running": session.status == "running",
      "notice": state.overflow ? LodyStrings.text("chat.notice.syncStopped") : "", "reconnect": state.overflow,
      "connection": connection,
      "placeholder": LodyStrings.text(session.archived ? "chat.composer.archived" : "chat.composer.placeholder"),
    ]))
    chat.setEmptyText(LodyStrings.text(state.status == "live" ? "chat.empty.prompt" : "chat.empty.loading"))
    guard state.entriesJSON != renderedEntries else { return }
    renderedEntries = state.entriesJSON
    chat.setEntries(state.entriesJSON)
    chat.scheduleUpdate()
  }

  private func projectName(_ session: SessionItem, catalog: SessionCatalog) -> String {
    if SessionRows.isChat(session.projectId) { return LodyStrings.text("inbox.section.chat") }
    return catalog.projects.first { $0.id == session.projectId }?.name ?? ""
  }

  private func titleMenu(_ session: SessionItem, machine: String, machineState: String) -> String {
    var items: [[String: Any]] = []
    if let branch = session.branchName {
      items.append([
        "id": "branch", "title": LodyStrings.text("session.title.copyBranch"), "subtitle": branch,
        "symbol": "arrow.triangle.branch",
      ])
    }
    if !machine.isEmpty {
      items.append([
        "id": "machine", "title": LodyStrings.text("session.title.machine"),
        "subtitle": "\(machine) · \(LodyStrings.text("devices.\(machineState)"))", "symbol": "desktopcomputer",
      ])
    }
    items.append(["id": "rename", "title": LodyStrings.text("session.action.rename"), "symbol": "pencil", "group": 1])
    guard let data = try? JSONSerialization.data(withJSONObject: items) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  private func updateMoreMenu(_ session: SessionItem) {
    let deleting = SessionActions.isDeleting(source.state.workspaceId, sessionId)
    let more = moreItem ?? UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: nil)
    more.accessibilityLabel = LodyStrings.text("common.more")
    more.menu = UIMenu(children: [
      UIAction(title: LodyStrings.text("session.action.find"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
        self?.find(query: "", keyboard: true)
      },
      UIAction(title: LodyStrings.text("session.action.share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
        self?.perform("share")
      },
      UIAction(
        title: LodyStrings.text(session.archived ? "session.action.unarchive" : "session.action.archive"),
        image: UIImage(systemName: session.archived ? "tray.and.arrow.up" : "archivebox")
      ) { [weak self] _ in self?.perform("archive") },
      UIMenu(options: .displayInline, children: [
        UIAction(
          title: LodyStrings.text(deleting ? "session.delete.pending" : "session.action.delete"),
          image: UIImage(systemName: "trash"), attributes: deleting ? [.destructive, .disabled] : .destructive
        ) { [weak self] _ in self?.perform("delete") },
      ]),
    ])
    moreItem = more
    let header = LodyNavigationHeader.of(navigationItem)
    if header.rightItems != [more] { header.rightItems = [more] }
  }

  private func wireEvents() {
    chat.onReconnect.onEventSent = { [weak self] _ in self?.feed?.reconnect() }
    chat.onTitleMenu.onEventSent = { [weak self] body in self?.titleMenuSelected(body["id"] as? String ?? "") }
  }

  private func titleMenuSelected(_ id: String) {
    switch id {
    case "branch":
      guard let branch = source.state.catalog.session(sessionId)?.branchName else { return }
      UIPasteboard.general.string = branch
      LodyToastOverlay.shared.show(message: LodyStrings.text("session.title.branchCopied"), kind: "info")
    case "rename":
      perform("rename")
    default:
      break
    }
  }

  private func perform(_ action: String) {
    actions.perform(action, row: sessionId, from: self)
  }

  private func find(query: String, keyboard: Bool) {
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
