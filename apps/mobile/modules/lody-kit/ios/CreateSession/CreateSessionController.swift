import UIKit

@MainActor
final class CreateSessionController: UIViewController {
  var form = CreateSessionForm()
  var loadOptions: ((_ projectId: String?) async throws -> CreationOptions)?
  var loadRepositories: (() async throws -> [CreateProject])?
  var browseProject: (() async -> CreateProject?)?
  var onPrefs: ((CreatePrefs) -> Void)?
  var onSelection: ((CreateSessionForm) -> Void)?
  var onSubmit: ((CreateSessionDraft?, [String: Any]) -> Void)?
  var onCancel: (() -> Void)?
  var showMessage: ((String) -> Void)?
  var restoreDraft: ((Int) -> Void)?
  private(set) var sending = false
  private var restoreToken = 0

  let composer: ChatComposerView
  private let host: UIView
  private let paged = LodyPagedList(appContext: nil)
  private let single = LodyGroupedList(appContext: nil)
  private lazy var hostHeight = host.heightAnchor.constraint(equalToConstant: 64)
  private var loads: [Bool: Task<Void, Never>] = [:]

  init(composer: ChatComposerView, host: UIView) {
    self.composer = composer
    self.host = host
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = LodyStrings.text("create.title")
    navigationItem.backButtonDisplayMode = .minimal
    let close = UIButton(type: .close)
    close.accessibilityLabel = LodyStrings.text("accessibility.closeSheet", ["title": LodyStrings.text("create.title")])
    close.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .primaryActionTriggered)
    close.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    navigationItem.rightBarButtonItem = UIBarButtonItem(customView: close)

    for list in [paged, single] as [UIView] {
      list.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(list)
      NSLayoutConstraint.activate([
        list.topAnchor.constraint(equalTo: view.topAnchor),
        list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }
    paged.setTransparent(true)
    single.setTransparent(true)
    paged.forwardedRowPress = { [weak self] in self?.rowPressed($0["id"] as? String ?? "") }
    paged.forwardedPageChange = { [weak self] in self?.pageChanged($0) }
    single.forwarded = { [weak self] name, body in
      if name == "rowPress" { self?.rowPressed(body["id"] as? String ?? "") }
    }

    host.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host)
    let keyboard = host.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
    keyboard.priority = .defaultHigh
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
      keyboard, hostHeight,
    ])
    composer.setInputIdentifier("create-session-input")
    composer.setComposerState(CreateJSON.encode(["placeholder": LodyStrings.text("create.composer.placeholder")]))
    render()
    load(chat: false)
    if !form.locked { load(chat: true) }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let inset = max(0, view.bounds.height - host.frame.minY)
    paged.setBottomInset(inset)
    single.setBottomInset(inset)
  }

  func setComposerHeight(_ height: CGFloat) {
    guard hostHeight.constant != height else { return }
    hostHeight.constant = height
    viewIfLoaded?.setNeedsLayout()
  }

  func render() {
    guard isViewLoaded else { return }
    let signedOut = form.signedOut
    paged.isHidden = form.locked || signedOut
    single.isHidden = !paged.isHidden
    if signedOut {
      single.setPlaceholder(LodyStrings.text("native.share.signIn"))
      single.setSections([])
    } else if form.locked {
      single.setSections(CreateSessionSections.root(form, page: form.project))
    } else {
      paged.setPages([
        page("project", "create.type.project", form.project),
        page("chat", "create.type.chat", form.chatPage),
      ])
      paged.setSelectedPage(form.chat ? 1 : 0)
    }
    renderComposer()
  }

  private func page(_ id: String, _ title: String, _ state: CreateSessionPage) -> LodyPagedPage {
    var page = LodyPagedPage()
    page.id = id
    page.title = LodyStrings.text(title)
    page.sections = CreateSessionSections.root(form, page: state)
    return page
  }

  private func renderComposer() {
    let page = form.current
    let capability = page.capability
    let fast = CreateLogic.fastMode(capability, page.choice)
    var options: [String: Any] = [
      "modelId": page.choice.modelId ?? "", "effort": page.choice.effort ?? "",
      "models": (capability?.models ?? []).map { ["id": $0.id, "title": $0.name] },
      "efforts": CreateLogic.effortsFor(capability, modelId: page.choice.modelId).map { ["id": $0, "title": $0] },
    ]
    if let fast { options["fast"] = fast.enabled }
    composer.setComposerOptions(Self.json(options))
    composer.setComposerState(Self.json([
      "editable": true, "canSend": form.canSend, "sending": sending, "notice": form.notice,
      "reconnect": false, "placeholder": LodyStrings.text("create.composer.placeholder"),
    ]))
  }

  private static func json(_ value: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  private func changed(prefs: Bool = true) {
    render()
    if prefs, let value = form.prefs { onPrefs?(value) }
    onSelection?(form)
  }

  func load(chat: Bool) {
    var page = chat ? form.chatPage : form.project
    if !chat && page.projectId.isEmpty { return }
    page.loading = true
    if chat { form.chatPage = page } else { form.project = page }
    render()
    let projectId = chat ? nil : page.projectId
    loads[chat]?.cancel()
    loads[chat] = Task { [weak self] in
      do {
        guard let options = try await self?.loadOptions?(projectId) else { return }
        guard let self, !Task.isCancelled, (chat ? nil : self.form.project.projectId) == projectId else { return }
        self.form.applyOptions(options, chat: chat)
        self.changed(prefs: false)
      } catch is CancellationError {
        return
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.form.failOptions(chat: chat)
        self.changed(prefs: false)
        self.showMessage?(LodyStrings.text("create.error.machineConfig"))
      }
    }
  }

  private func pageChanged(_ index: Int) {
    guard !sending else {
      paged.setSelectedPage(form.chat ? 1 : 0)
      return
    }
    form.switchPage(chat: index == 1)
    changed()
  }

  private func rowPressed(_ id: String) {
    guard !sending else { return }
    let page = form.current
    switch id {
    case "project": pickProject()
    case "machine", "agent":
      guard page.options != nil else { return load(chat: form.chat) }
      id == "machine" ? pickMachine() : pickAgent()
    case "model": pickModel()
    case "branch": editBranch()
    default: break
    }
  }

  private func push(_ controller: UIViewController) {
    navigationController?.pushViewController(controller, animated: true)
  }

  private func pickProject() {
    let picker = CreateProjectPickerController(
      projects: form.projects, machineNames: form.machineNames, selectedId: form.project.projectId,
      loadRepositories: loadRepositories, browse: browseProject)
    picker.onPick = { [weak self, weak picker] project in
      guard let self else { return }
      picker?.navigationController?.popViewController(animated: true)
      let changedProject = project.id != self.form.project.projectId
      self.form.selectProject(project)
      if changedProject { self.load(chat: false) }
      self.changed(prefs: false)
    }
    push(picker)
  }

  private func pickMachine() {
    let page = form.current
    push(CreateChoiceController(
      title: LodyStrings.text("create.row.selectMachine"), header: LodyStrings.text("create.label.machine"),
      placeholder: LodyStrings.text("create.picker.machine.placeholder"),
      options: page.machines.map { ($0.id, $0.name, "") }, selected: page.machine?.id
    ) { [weak self] id in
      self?.form.selectMachine(id)
      self?.changed()
    })
  }

  private func pickAgent() {
    let page = form.current
    push(CreateChoiceController(
      title: LodyStrings.text("create.row.selectAgent"), header: LodyStrings.text("create.label.agent"),
      placeholder: LodyStrings.text("create.picker.agent.placeholder"),
      options: page.agents.map { ($0.key, $0.name, $0.machineName) }, selected: page.agentKey
    ) { [weak self] key in
      self?.form.selectAgent(key)
      self?.changed()
    })
  }

  private func pickModel() {
    let page = form.current
    guard let capability = page.capability else { return }
    let title = CreateModelOptions.hasTabs(capability)
      ? (page.agent?.name ?? LodyStrings.text("model.title"))
      : LodyStrings.text("create.row.selectModel")
    let controller = CreateModelController(capability: capability, choice: page.choice)
    controller.title = title
    controller.choiceForModel = { [weak self] modelId in
      guard let self else { return ModelChoice(modelId: modelId) }
      return CreateLogic.rememberedModelChoice(
        self.form.prefs, agentKey: self.form.current.agentKey, capability: capability, modelId: modelId)
    }
    controller.onChange = { [weak self] choice in
      self?.form.updateChoice(choice)
      self?.changed()
    }
    push(controller)
  }

  private func editBranch() {
    let alert = UIAlertController(
      title: LodyStrings.text("create.branch.label"), message: LodyStrings.text("create.branch.placeholder"),
      preferredStyle: .alert)
    alert.addTextField { [weak self] field in field.text = self?.form.project.branch }
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default) { [weak self, weak alert] _ in
      let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
      self?.form.project.branch = String(value.prefix(255))
      self?.changed(prefs: false)
    })
    present(alert, animated: true)
  }

  func composerOptionChanged(_ body: [String: Any]) {
    let page = form.current
    if let fast = body["fast"] as? Bool {
      form.updateChoice(CreateLogic.withFastMode(page.capability, page.choice, enabled: fast))
    } else {
      let modelId = (body["modelId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      if modelId != page.choice.modelId {
        form.selectModel(modelId)
      } else {
        var next = page.choice
        next.effort = (body["effort"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        form.updateChoice(next)
      }
    }
    changed()
  }

  @discardableResult
  func submit(_ payload: [String: Any]) -> Bool {
    let text = payload["text"] as? String ?? ""
    let attachments = payload["attachments"] as? [Any] ?? []
    let draft = form.current.options.flatMap { form.draft(sessionId: $0.sessionId) }
    guard !sending, form.canSend, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
      draft != nil || form.deferUnresolved
    else {
      restore()
      return false
    }
    if form.current.github && form.current.branch.trimmingCharacters(in: .whitespaces).isEmpty {
      restore()
      message(LodyStrings.text("create.toast.branchRequired"))
      return false
    }
    form.updateChoice(form.current.choice)
    if let value = form.prefs { onPrefs?(value) }
    sending = true
    renderComposer()
    onSubmit?(draft, payload)
    return true
  }

  func submissionFailed() {
    sending = false
    restore()
    renderComposer()
  }

  private func restore() {
    restoreToken += 1
    if let restoreDraft { restoreDraft(restoreToken) } else { composer.restoreDraft(token: restoreToken) }
  }

  func message(_ text: String) {
    if let showMessage { return showMessage(text) }
    let alert = UIAlertController(title: text, message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default))
    present(alert, animated: true)
  }
}
