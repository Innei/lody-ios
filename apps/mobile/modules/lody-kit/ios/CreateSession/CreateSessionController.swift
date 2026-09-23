import UIKit

/// The same native form in an Expo presentation and a Share Extension.
@MainActor
final class CreateSessionController: UIViewController, UICollectionViewDelegate {
  let composer: ChatComposerView
  private let composerHost: UIView
  private let ownsComposer: Bool
  var form = CreateSessionForm()
  var onSubmit: ([String: Any]) -> Void = { _ in }
  var onRejected: (() -> Void)?
  var onPreferences: ([String: Any]) -> Void = { _ in }
  var onSelection: (String) -> Void = { _ in }
  var onRecovery: (() -> Void)?
  var recoveryTitle: String?
  var busy = false { didSet { render() } }
  var submissionLocked = false { didSet { render() } }
  var notice = "" { didSet { render() } }
  private let context = UISegmentedControl(items: [LodyStrings.text("native.create.projects"), LodyStrings.text("native.create.chat")])
  private var collection: UICollectionView!
  private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
  private var footerHeight: NSLayoutConstraint!
  private var rows: [(id: String, title: String, detail: String, action: () -> Void)] = []

  init(composer: ChatComposerView? = nil, host: UIView? = nil) {
    let input = composer ?? ChatComposerView(frame: .zero)
    self.composer = input; composerHost = host ?? input; ownsComposer = host == nil
    super.init(nibName: nil, bundle: nil)
    if ownsComposer {
      input.sendHandoff = false
      input.prepareSend = { [weak self] payload in self?.submit(payload); return true }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    view.tintColor = .systemBlue
    title = LodyStrings.text("native.create.title")
    context.selectedSegmentIndex = form.chat ? 1 : 0
    context.accessibilityIdentifier = "create-context"
    context.addAction(UIAction { [weak self] _ in
      guard let self, !self.busy else { return }
      self.form.remember(); self.form.chat = self.context.selectedSegmentIndex == 1
      self.form.restore(); self.changed()
    }, for: .valueChanged)
    var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    config.backgroundColor = .systemGroupedBackground
    collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
    collection.delegate = self
    collection.accessibilityIdentifier = "create-form"
    collection.keyboardDismissMode = .interactive
    LodyScrollEdges.bind(collection, to: self)
    LodyScrollEdges.navigation(collection)
    let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
      guard let row = self?.rows.first(where: { $0.id == id }) else { return }
      var content = UIListContentConfiguration.valueCell()
      content.text = row.title; content.secondaryText = row.detail
      cell.contentConfiguration = content
      cell.accessories = [.disclosureIndicator()]
      cell.accessibilityIdentifier = id
      cell.accessibilityLabel = row.title + ", " + row.detail
    }
    dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { view, path, id in
      view.dequeueConfiguredReusableCell(using: registration, for: path, item: id)
    }
    for item in [context, collection!, composerHost] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
    footerHeight = composerHost.heightAnchor.constraint(equalToConstant: 100)
    NSLayoutConstraint.activate([
      context.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      context.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      context.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      context.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
      collection.topAnchor.constraint(equalTo: context.bottomAnchor, constant: 8),
      collection.leadingAnchor.constraint(equalTo: view.leadingAnchor), collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collection.bottomAnchor.constraint(equalTo: composerHost.topAnchor),
      composerHost.leadingAnchor.constraint(equalTo: view.leadingAnchor), composerHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      composerHost.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), footerHeight,
    ])
    if ownsComposer { composer.onHeightChange = { [weak self] in self?.setComposerHeight($0) } }
    composer.setInputIdentifier("create-session-input")
    composer.attachScrollEdge(to: collection)
    render()
  }
  func setComposerHeight(_ height: CGFloat) { footerHeight?.constant = height; viewIfLoaded?.setNeedsLayout() }
  func configure(_ snapshot: [String: Any]) {
    let first = form.snapshot.isEmpty
    form.snapshot = snapshot
    if first {
      form.prefs = snapshot["prefs"] as? [String: Any] ?? [:]
      form.chat = snapshot["context"] as? String == "chat"
      form.projectID = snapshot["projectId"] as? String ?? form.prefs["projectId"] as? String ?? form.projects.first?["id"] as? String ?? ""
      form.restore()
    } else if form.agent == nil { form.restore() }
    onSelection(form.chat ? "" : form.projectID)
    render()
  }
  func submit(_ payload: [String: Any]) {
    guard !busy, !submissionLocked, let draft = form.draft(payload) else { reject(); return }
    let attachments = payload["attachments"] as? [[String: Any]] ?? []
    guard attachments.count <= 16, attachments.filter({ $0["kind"] as? String == "image" }).count <= 8,
      attachments.filter({ $0["kind"] as? String == "file" }).count <= 8,
      (payload["text"] as? String ?? "").utf8.count <= 65536 else {
      notice = LodyStrings.text("native.create.limits"); reject(); return
    }
    form.remember(); onPreferences(form.prefs); onSubmit(draft)
  }
  private func reject() {
    if let onRejected { onRejected() }
    else { composer.restoreRejectedDraft() }
  }
  private func changed() {
    form.remember(); onPreferences(form.prefs)
    try? ShareStore.savePreferences(form.prefs, user: form.userID, workspace: form.workspaceID)
    onSelection(form.chat ? "" : form.projectID); render()
  }
  func render() {
    guard isViewLoaded else { return }
    context.isEnabled = !busy; context.selectedSegmentIndex = form.chat ? 1 : 0
    rows = []
    if !form.chat {
      rows.append(("project", LodyStrings.text("native.create.project"), form.project?["name"] as? String ?? LodyStrings.text("native.create.select"), { [weak self] in self?.pickProjects() }))
      if form.projectID.hasPrefix("github:") { rows.append(("branch", LodyStrings.text("native.create.branch"), form.branch, { [weak self] in self?.editBranch() })) }
    }
    rows.append(("machine", LodyStrings.text("native.create.machine"), form.agent?["machineName"] as? String ?? LodyStrings.text("native.create.select"), { [weak self] in self?.pickMachines() }))
    rows.append(("agent", LodyStrings.text("native.create.agent"), form.agent?["name"] as? String ?? LodyStrings.text("native.create.select"), { [weak self] in self?.pickAgents() }))
    rows.append(("model", LodyStrings.text("native.create.modelOptions"), form.modelSummary, { [weak self] in self?.pickModel() }))
    if onRecovery != nil { rows.append(("recovery", recoveryTitle ?? LodyStrings.text("native.create.previous"), LodyStrings.text("native.create.check"), { [weak self] in self?.onRecovery?() })) }
    var snapshot = NSDiffableDataSourceSnapshot<Int, String>(); snapshot.appendSections([0]); snapshot.appendItems(rows.map(\.id))
    snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { dataSource.snapshot().itemIdentifiers.contains($0) })
    dataSource.apply(snapshot, animatingDifferences: false)
    var message = notice
    if message.isEmpty && form.userID.isEmpty { message = LodyStrings.text("native.create.signIn") }
    if message.isEmpty && form.agent == nil { message = LodyStrings.text("native.create.refresh") }
    composer.setComposerState(createJSON(["editable": !busy && !submissionLocked, "canSend": form.canSend && !busy && !submissionLocked,
      // Loading and receipt recovery must never consume an unrelated draft.
      // Actual sends are owned by the native relay or the extension receipt.
      "sending": false, "notice": message, "reconnect": false, "placeholder": LodyStrings.text("native.chat.composer.placeholder")]))
    var composerOptions: [String: Any] = ["modelId": form.choice["modelId"] ?? "", "effort": form.choice["effort"] ?? "",
      "models": (form.capability["models"] as? [[String: Any]] ?? []).map { ["id": $0["id"] ?? "", "title": $0["name"] ?? ""] },
      "efforts": form.efforts.map { ["id": $0, "title": $0] }]
    if let fast = form.configOptions.first(where: { ["fast-mode", "fast"].contains($0["id"] as? String ?? "") && $0["type"] as? String == "boolean" }), let id = fast["id"] as? String {
      composerOptions["fast"] = (form.choice["configOptionValues"] as? [String: Any])?[id] ?? fast["currentValue"] ?? false
    }
    composer.setComposerOptions(createJSON(composerOptions))
    composer.onComposerOptionChange = { [weak self] value in
      guard let self else { return }
      let model = value["modelId"] as? String ?? ""
      if model != (self.form.choice["modelId"] as? String ?? "") { self.form.selectModel(model) }
      else { self.form.choice["effort"] = value["effort"] }
      if let fast = value["fast"] as? Bool, let id = self.form.configOptions.first(where: { ["fast-mode", "fast"].contains($0["id"] as? String ?? "") })?["id"] as? String {
        var values = self.form.choice["configOptionValues"] as? [String: Any] ?? [:]
        values[id] = fast; self.form.choice["configOptionValues"] = values
      }
      self.changed()
    }
  }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard !busy, indexPath.item < rows.count else { collectionView.deselectItem(at: indexPath, animated: true); return }
    rows[indexPath.item].action()
    if presentedViewController != nil { collectionView.deselectItem(at: indexPath, animated: true) }
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard let selected = collection?.indexPathsForSelectedItems?.first else { return }
    if let transitionCoordinator {
      transitionCoordinator.animate(alongsideTransition: { [weak self] _ in self?.collection.deselectItem(at: selected, animated: animated) }) { [weak self] context in
        if context.isCancelled { self?.collection.selectItem(at: selected, animated: false, scrollPosition: []) }
      }
    } else { collection.deselectItem(at: selected, animated: animated) }
  }
  private func pick(_ title: String, items: [(String, String)], selected: String, action: @escaping (String) -> Void) {
    let picker = CreateSessionPicker(title: title, items: items, selected: selected, onPick: action)
    if let navigationController { navigationController.pushViewController(picker, animated: true) }
    else { present(UINavigationController(rootViewController: picker), animated: true) }
  }
  private func pickProjects() {
    let page = CreateSessionPicker(title: LodyStrings.text("native.create.project"), items: form.projects.map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }, selected: form.projectID) { [weak self] id in
      guard let self else { return }; self.form.projectID = id; self.form.branch = ""; self.form.restore(); self.changed()
    }
    if let navigationController { navigationController.pushViewController(page, animated: true) }
    else { present(UINavigationController(rootViewController: page), animated: true) }
    guard !LodyUIVerify.enabled else { return }
    let workspace = form.workspaceID
    Task { [weak self, weak page] in
      do {
        let repositories = try await GitHubCloud.repositories(workspace: workspace)
        guard let self, let page, self.form.workspaceID == workspace else { return }
        self.form.discoveredProjects = repositories.map { ["id": "github:" + $0, "name": $0, "machineId": "", "rootPath": ""] }
        page.replace(self.form.projects.map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") })
      } catch { page?.navigationItem.prompt = LodyStrings.text("native.create.repositoriesUnavailable") }
    }
  }
  private func pickMachines() {
    var seen = Set<String>()
    let machines = form.agents.compactMap { agent -> (String, String)? in
      let id = agent["machineId"] as? String ?? ""
      return seen.insert(id).inserted ? (id, agent["machineName"] as? String ?? id) : nil
    }
    pick(LodyStrings.text("native.create.machine"), items: machines, selected: form.agent?["machineId"] as? String ?? "") { [weak self] id in
      guard let self else { return }
      self.form.agentKey = self.form.agents.first { $0["machineId"] as? String == id }.map(CreateSessionForm.key) ?? ""
      self.form.choice = [:]; self.form.restoreModel(); self.changed()
    }
  }
  private func pickAgents() {
    let machine = form.agent?["machineId"] as? String
    pick(LodyStrings.text("native.create.agent"), items: form.agents.filter { $0["machineId"] as? String == machine }.map { (CreateSessionForm.key($0), $0["name"] as? String ?? "") }, selected: form.agentKey) { [weak self] id in
      self?.form.agentKey = id; self?.form.choice = [:]; self?.form.restoreModel(); self?.changed()
    }
  }
  private func editBranch() {
    let alert = UIAlertController(title: LodyStrings.text("native.create.branch"), message: nil, preferredStyle: .alert)
    alert.addTextField { $0.text = self.form.branch; $0.placeholder = "main"; $0.autocapitalizationType = .none }
    alert.addAction(UIAlertAction(title: LodyStrings.text("native.create.cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: LodyStrings.text("native.create.save"), style: .default) { [weak self] _ in
      self?.form.branch = String((alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(255)); self?.changed()
    }); present(alert, animated: true)
  }
  private func pickModel() {
    let page = CreateSessionOptionsController(form: form) { [weak self] choice in
      self?.form = choice; self?.changed()
    }
    if let navigationController { navigationController.pushViewController(page, animated: true) }
    else { present(UINavigationController(rootViewController: page), animated: true) }
  }
}

@MainActor
final class CreateSessionPicker: UICollectionViewController, UISearchResultsUpdating {
  private var items: [(String, String)]
  private var visible: [(String, String)] { let query = navigationItem.searchController?.searchBar.text ?? ""; return items.filter { query.isEmpty || $0.1.localizedCaseInsensitiveContains(query) } }
  private let selected: String
  private let onPick: (String) -> Void
  init(title: String, items: [(String, String)], selected: String, onPick: @escaping (String) -> Void) {
    self.items = items; self.selected = selected; self.onPick = onPick
    super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: .insetGrouped)))
    self.title = title
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private lazy var registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [weak self] cell, _, index in
    guard let self else { return }
    var content = UIListContentConfiguration.cell(); content.text = self.visible[index].1
    cell.contentConfiguration = content; cell.accessories = self.visible[index].0 == self.selected ? [.checkmark()] : []
    cell.accessibilityIdentifier = self.visible[index].0.isEmpty ? "default-choice" : self.visible[index].0
  }
  override func viewDidLoad() {
    super.viewDidLoad(); LodyScrollEdges.bind(collectionView, to: self); LodyScrollEdges.navigation(collectionView)
    _ = registration
    let search = UISearchController(); search.searchResultsUpdater = self
    search.obscuresBackgroundDuringPresentation = false; navigationItem.searchController = search
    definesPresentationContext = true
  }
  func replace(_ items: [(String, String)]) { self.items = items; collectionView.reloadData() }
  func updateSearchResults(for searchController: UISearchController) { collectionView.reloadData() }
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { visible.count }
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: indexPath.item)
  }
  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    onPick(visible[indexPath.item].0)
    collectionView.deselectItem(at: indexPath, animated: true)
    if navigationController?.viewControllers.first === self { dismiss(animated: true) }
    else { navigationController?.popViewController(animated: true) }
  }
}
