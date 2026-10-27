import UIKit

@MainActor
final class InboxController: UIViewController {
  let list = SessionListView()
  let source: SessionSource
  private let chrome = InboxChrome()
  private lazy var actions = SessionActions(source: source)
  private var mode = InboxController.storedIndex("inboxView")
  private var sort = InboxSort.allCases[InboxController.storedIndex("inboxProjectSort")]
  private var expanded = UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
  private var query = ""
  private var search: (key: String, catalog: SessionCatalog, hits: InboxSearchHits)?
  private var requested: (key: String, catalog: SessionCatalog)?
  private var searchTask: Task<Void, Never>?
  private var views: [String: Double] = [:]
  private var viewsKey = ""
  private var viewsLoad = 0
  private var observers: [NSObjectProtocol] = []

  init(source: SessionSource = .live) {
    self.source = source
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    searchTask?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    loadPreferences()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.accessibilityIdentifier = "ipad-inbox-list"
    list.setContentStyle(true)
    list.forwarded = { [weak self] name, body in self?.event(name, body) }
    view.addSubview(list)
    wireChrome()
    observers = (source.changes + [UIApplication.didBecomeActiveNotification]).map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.render() }
      }
    }
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in self.render() }
    // UI Verify can reset the prefs after this controller has already read them.
    observers.append(NotificationCenter.default.addObserver(forName: .lodyInboxPreferencesReset, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.reloadPreferences() }
    })
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    chrome.layout()
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    if let parent {
      chrome.attach(to: parent)
      render()
    } else {
      chrome.detach()
    }
  }

  func render() {
    guard isViewLoaded else { return }
    let state = source.state
    loadViews(state)
    guard !state.userId.isEmpty else {
      chrome.update(nil)
      list.setPlaceholder("")
      list.setSections([])
      return
    }
    let catalog = state.catalog.viewed(views)
    chrome.update(InboxChrome.Model(
      workspaces: state.workspaces, selected: state.workspace,
      devices: InboxDevices(catalog: state.catalog, presence: state.presence), mode: mode, sort: sort
    ))
    list.setPreviewUserId(state.userId)
    list.setPreviewWorkspaceId(state.workspaceId)
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.isEmpty else {
      renderSearch(term, state: state, catalog: catalog)
      return
    }
    list.setPlaceholder(listPlaceholder(state))
    let pinOrder = pinOrder(state, catalog: catalog)
    if mode == 0 {
      list.setSections(InboxSections.projects(catalog, expanded: expanded, sort: sort, pinOrder: pinOrder))
    } else {
      list.setSections(InboxSections.inbox(catalog, chatOnly: mode == 2, pinOrder: pinOrder))
    }
  }

  private func wireChrome() {
    chrome.selectWorkspace = { [weak self] id in self?.selectWorkspace(id) }
    chrome.editWorkspace = { [weak self] in self?.editWorkspace() }
    chrome.setView = { [weak self] mode in self?.setView(mode) }
    chrome.setSort = { [weak self] sort in
      guard let self else { return }
      self.sort = sort
      UserDefaults.standard.set(InboxSort.allCases.firstIndex(of: sort) ?? 0, forKey: "inboxProjectSort")
      self.render()
    }
    // JS presents these so deep links that reset the stack also dismiss them.
    chrome.openSettings = { [weak self] in
      LodyShell.shared.openPage("settings", options: ["present": true], from: self?.parent)
    }
    chrome.openDebug = { [weak self] in LodyShell.shared.openPage("debug", from: self?.parent) }
    chrome.newSession = { [weak self] in self?.newSession() }
    chrome.searchChanged = { [weak self] text in
      guard let self, text != self.query else { return }
      self.query = text
      self.render()
    }
  }

  private func renderSearch(_ term: String, state: SessionListState, catalog: SessionCatalog) {
    let key = [state.userId, state.workspaceId, term].joined(separator: "\0")
    if requested?.key != key || requested?.catalog != catalog { requestSearch(term, key: key, state: state, catalog: catalog) }
    let current = search.flatMap { $0.key == key && $0.catalog == catalog ? $0 : nil }
    list.setPlaceholder(LodyStrings.text(current == nil ? "search.placeholder.loading" : "search.placeholder.noMatch"))
    list.setSections(InboxSections.search(catalog, hits: current?.hits ?? InboxSearchHits()))
  }

  private func requestSearch(_ term: String, key: String, state: SessionListState, catalog: SessionCatalog) {
    requested = (key, catalog)
    searchTask?.cancel()
    guard !state.workspaceId.isEmpty else { return }
    let (user, workspace) = (state.userId, state.workspaceId)
    searchTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      let result: Result<InboxSearchHits, Error> = await withCheckedContinuation { done in
        LocalStore.queue.async {
          done.resume(returning: Result {
            Self.hits(try LocalStore.shared.searchInbox(userID: user, workspaceID: workspace, query: term))
          })
        }
      }
      guard let self, !Task.isCancelled, self.requested?.key == key else { return }
      switch result {
      case .success(let hits):
        self.search = (key, catalog, hits)
      case .failure:
        LodyToastOverlay.shared.show(message: LodyStrings.text("search.toast.failed"), kind: "error")
        self.search = (key, catalog, InboxSections.match(catalog, keyword: term))
      }
      self.render()
    }
  }

  private nonisolated static func hits(_ raw: [String: Any]) -> InboxSearchHits {
    let sessions = (raw["sessions"] as? [[String: Any]] ?? []).compactMap { item -> (id: String, snippet: String?)? in
      guard let id = item["id"] as? String else { return nil }
      return (id, item["snippet"] as? String)
    }
    return InboxSearchHits(projectIds: raw["projectIds"] as? [String] ?? [], sessions: sessions)
  }

  private func listPlaceholder(_ state: SessionListState) -> String {
    if state.loading { return LodyStrings.text("sessions.placeholder.loading") }
    if !state.connected { return LodyStrings.text("sessions.placeholder.offline") }
    return LodyStrings.text("sessions.placeholder.empty")
  }

  private func pinOrder(_ state: SessionListState, catalog: SessionCatalog) -> [String] {
    let key = "inboxPinOrder.\(state.userId).\(state.workspaceId)"
    let stored = state.workspaceId.isEmpty ? [] : UserDefaults.standard.stringArray(forKey: key) ?? []
    let activity = Dictionary(catalog.sessions.map { ($0.id, $0.activityAt) }, uniquingKeysWith: { first, _ in first })
    let order = InboxSections.reconcilePinOrder(
      stored, pinned: catalog.sessions.filter(\.pinned).map(\.id), activity: { activity[$0] ?? 0 }
    )
    if !state.workspaceId.isEmpty, order != stored { UserDefaults.standard.set(order, forKey: key) }
    return order
  }

  private func loadViews(_ state: SessionListState) {
    if state.key != viewsKey {
      viewsKey = state.key
      views = [:]
    }
    viewsLoad += 1
    let load = viewsLoad
    Task { [weak self] in
      let next = await SessionSource.views(userId: state.userId, workspaceId: state.workspaceId)
      guard let self, self.viewsLoad == load, next != self.views else { return }
      self.views = next
      self.render()
    }
  }

  private func event(_ name: String, _ body: [String: Any]) {
    guard let id = body["id"] as? String else { return }
    switch name {
    case "rowPress":
      if consume(id, expanded: body["expanded"] as? Bool ?? true) { return }
      let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
      actions.open(id, findQuery: term.isEmpty ? nil : term, from: self)
    case "rowAction":
      guard let action = body["actionId"] as? String else { return }
      actions.perform(action, row: id, from: self)
    default:
      break
    }
  }

  private func consume(_ id: String, expanded open: Bool) -> Bool {
    if id == "view:\(InboxSections.chatId)" {
      setView(2)
      return true
    }
    if id.hasPrefix("toggle:") {
      let project = String(id.dropFirst(7))
      expanded[project] = open
      var stored = UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
      stored[project] = open
      UserDefaults.standard.set(stored, forKey: "inboxExpansion")
      render()
      return true
    }
    return InboxSections.isChatRow(id)
  }

  private func setView(_ next: Int) {
    mode = next
    UserDefaults.standard.set(next, forKey: "inboxView")
    render()
  }

  private func selectWorkspace(_ id: String) {
    guard LodyPreviewBridge.active else {
      CatalogSession.shared.selectWorkspace(id)
      return
    }
    Task { try? await LodyPreviewBridge.request("selectWorkspace", ["workspaceId": id]) }
  }

  private func editWorkspace() {
    guard let workspace = source.state.workspace else { return }
    var params: [String: Any] = [
      "workspaceId": workspace.id, "name": workspace.name,
      "color": LodyAccentChoice.hex(UIColor.lodyAccent.resolvedColor(with: traitCollection)),
    ]
    params["image"] = workspace.image
    let json = (try? JSONSerialization.data(withJSONObject: params)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    LodyShell.shared.openPage("workspace-editor", params: json, options: ["present": true], from: parent)
  }

  private func newSession() {
    let state = source.state
    guard state.workspace != nil else {
      LodyToastOverlay.shared.show(message: LodyStrings.text("tabs.toast.signInFirst"), kind: "error")
      return
    }
    SessionActions.create(["workspaceId": state.workspaceId, "zoomSourceLabel": LodyStrings.text("tabs.newSession")])
  }

  private func loadPreferences() {
    mode = Self.storedIndex("inboxView")
    sort = InboxSort.allCases[Self.storedIndex("inboxProjectSort")]
    expanded = UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
  }

  private func reloadPreferences() {
    loadPreferences()
    render()
  }

  private static func storedIndex(_ key: String) -> Int {
    let value = UserDefaults.standard.integer(forKey: key)
    return (0...2).contains(value) ? value : 0
  }
}

extension Notification.Name {
  static let lodyInboxPreferencesReset = Notification.Name("LodyInboxPreferencesReset")
}
