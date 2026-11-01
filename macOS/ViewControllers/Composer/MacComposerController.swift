import AppKit
import LodyCore
import LodyData

@MainActor
final class MacComposerController: NSViewController, NSTextViewDelegate {
  private(set) var model: MacComposerModel
  private let service: MacComposerService
  private let view1 = MacComposerView()
  private var optionsTask: Task<Void, Never>?
  private var draft = MacDraftHandoff()
  private var draftScope: MacDraftStore.Scope?
  private var draftStore: MacDraftStore?
  private let draftOwner = UUID().uuidString
  private var draftObserver: NSObjectProtocol?
  private var sentId: String?
  private var persistenceFailed = false
  private let optionsPanel = MacComposerOptionsController()
  private let optionsPopover = NSPopover()
  var onReplyChoice: (([String: Any]) -> Void)?
  var onSend: (() -> Void)?
  var onStop: (() -> Void)?
  var onQueue: (() -> Void)?
  var onChanges: (() -> Void)? {
    didSet { view1.onChanges = onChanges; render() }
  }
  var onProjectChange: ((_ userInitiated: Bool) -> Void)?
  var onChooseProject: (() -> Void)?
  private var inheritedMachineId: String?
  private var configured = false

  var hasDraft: Bool { !model.text.isEmpty || !model.attachments.isEmpty || configured }

  func focusInput() { view.window?.makeFirstResponder(view1.input) }
  func showProjects() {
    if let onChooseProject { onChooseProject() }
    else { view1.project.performClick(nil) }
  }

  func selectProject(_ id: String?, machineId: String? = nil, userInitiated: Bool = true) {
    guard model.mode == .newSession else { return }
    if let id, let project = model.form.projects.first(where: { $0.id == id }) {
      model.form.switchPage(chat: false)
      model.form.selectProject(project)
    } else if id == nil {
      model.form.switchPage(chat: true)
    } else { return }
    if userInitiated { configured = true }
    inheritedMachineId = machineId
    persistDraft()
    render()
    onProjectChange?(userInitiated)
    if isViewLoaded { loadOptions() }
  }
  var replyContext: (project: String, branch: String, machine: String) = ("", "", "") {
    didSet { render() }
  }

  init(model: MacComposerModel, service: MacComposerService) {
    self.model = model
    self.service = service
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit { if let draftObserver { NotificationCenter.default.removeObserver(draftObserver) } }

  func bindDraft(_ scope: MacDraftStore.Scope, store: MacDraftStore = .shared) {
    guard !scope.user.isEmpty, !scope.workspace.isEmpty else { return }
    if let draftObserver { NotificationCenter.default.removeObserver(draftObserver) }
    draftScope = scope
    draftStore = store
    loadDraft()
    draftObserver = NotificationCenter.default.addObserver(forName: MacDraftStore.changed, object: store, queue: .main) { [weak self] note in
      let scopeKey = note.userInfo?["scope"] as? String
      let sender = note.userInfo?["owner"] as? String
      MainActor.assumeIsolated {
        guard let self, !self.persistenceFailed, store.ownsNotification(scopeKey: scopeKey, sender: sender, scope: scope, owner: self.draftOwner) else { return }
        self.loadDraft()
      }
    }
  }

  private func loadDraft() {
    guard let draftScope, let draftStore else { return }
    do {
      let loaded = try draftStore.load(draftScope)
      model.text = loaded?.record.text ?? ""
      model.attachments.restore(loaded?.attachments ?? [])
      if let selection = loaded?.record.selection, model.mode == .newSession {
        model.form.prefs = selection.prefs
        model.form.open(projectId: selection.projectId.isEmpty ? nil : selection.projectId, context: selection.chat ? "chat" : nil)
        if isViewLoaded { loadOptions() }
      }
      if isViewLoaded { view1.input.string = model.text }
      model.attachmentNotice = model.attachments.items.contains(where: { !FileManager.default.fileExists(atPath: $0.url.path) })
        ? String(localized: "mac.draft.missing", bundle: .lodyMac) : ""
      render()
      onProjectChange?(false)
    } catch { draftError() }
  }

  @discardableResult
  private func persistDraft() -> Bool {
    guard let draftScope, let draftStore else { return true }
    do {
      var selection: MacDraftStore.Selection?
      if model.mode == .newSession { selection = .init(projectId: model.form.project.projectId, chat: model.form.chat, prefs: model.form.prefs) }
      let saved = try draftStore.save(draftScope, text: model.text, attachments: model.attachments.items, selection: selection, owner: draftOwner)
      model.attachments.restore(saved.attachments)
      persistenceFailed = false
      return true
    } catch { draftError(); return false }
  }

  private func draftError() {
    persistenceFailed = true
    model.attachmentNotice = String(localized: "mac.draft.failed", bundle: .lodyMac)
    render()
  }

  private func handoff(_ id: String) -> Bool {
    guard persistDraft() else { return false }
    do {
      if let draftStore, let draftScope { try draftStore.handoff(draftScope, sendId: id) }
      sentId = id
      return true
    } catch { draftError(); return false }
  }

  func reconcileDraft(pending: String?, delivered: Set<String>, uploaded: Bool) {
    guard let draftScope, let draftStore else { return }
    do {
      if let pending, draftStore.matchesHandoff(draftScope, sendId: pending, text: model.text, ids: model.attachments.items.map(\.id)) {
        clearInput()
      }
      var confirmed = delivered
      if uploaded, let pending { confirmed.insert(pending) }
      try draftStore.settle(draftScope, delivered: confirmed)
      try draftStore.settle(.init(user: draftScope.user, workspace: draftScope.workspace, session: "new"), delivered: confirmed)
    } catch { draftError() }
  }

  override func loadView() {
    view = view1
    view1.input.string = model.text
    view1.input.delegate = self
    view1.onSend = { [weak self] in self?.send() }
    view1.onStop = { [weak self] in self?.onStop?() }
    view1.onQueue = { [weak self] in self?.onQueue?() }
    view1.onDropFiles = { [weak self] in self?.addFiles($0) }
    view1.input.onDropFiles = { [weak self] in self?.addFiles($0) }
    view1.input.onPasteAttachments = { [weak self] in self?.paste($0) ?? false }
    view1.attach.target = self
    view1.attach.action = #selector(pickFiles)
    view1.strip.onRemove = { [weak self] in self?.removeAttachment($0.id) }
    view1.project.target = self
    view1.project.action = #selector(projectChanged)
    view1.project.onOpen = { [weak self] in
      guard let choose = self?.onChooseProject else { return false }
      choose()
      return true
    }
    view1.machine.target = self
    view1.machine.action = #selector(machineChanged)
    view1.agent.target = self
    view1.agent.action = #selector(agentChanged)
    view1.mode.target = self
    view1.mode.action = #selector(choiceChanged)
    view1.modelPicker.target = self
    view1.modelPicker.action = #selector(showOptions)
    optionsPopover.behavior = .transient
    optionsPopover.contentViewController = optionsPanel
    optionsPanel.onResize = { [weak self] size in self?.optionsPopover.contentSize = size }
    optionsPanel.onFast = { [weak self] enabled in
      guard let self else { return }
      if model.mode == .newSession {
        configured = true
        model.form.updateChoice(CreateLogic.withFastMode(model.capability, model.choice, enabled: enabled))
      } else {
        onReplyChoice?(["fast": enabled])
      }
      render()
    }
    optionsPanel.onChange = { [weak self] choice in self?.applyChoice(choice) }
    render()
    if model.mode == .newSession { loadOptions() }
  }

  func updateReply(ready: Bool, capability: Capability?, choice: ModelChoice?) {
    model.replyReady = ready
    model.replyCapability = capability
    if let choice { model.replyChoice = choice }
    render()
  }

  func updateRun(_ state: SessionControl.State) {
    model.run = state
    render()
  }

  func updateQueueCount(_ count: Int) {
    model.queueCount = count
    render()
  }

  func updateCatalog(projects: [CreateProject], machineNames: [String: String], reload: Bool) {
    model.form.projects = projects
    model.form.machineNames = machineNames
    render()
    if reload || model.form.current.failed { loadOptions() }
  }

  func restoreDraft() {
    guard let restored = draft.restore(current: view1.input.string, hasAttachments: !model.attachments.isEmpty) else { return }
    view1.input.string = restored.text
    model.text = restored.text
    model.attachments.restore(restored.attachments)
    if persistDraft(), let sentId, let draftScope, let draftStore { try? draftStore.complete(draftScope, sendId: sentId) }
    sentId = nil
    render()
  }

  func addFiles(_ urls: [URL]) {
    let rejections = model.attachments.add(urls: urls)
    model.attachmentNotice = rejections.first?.message ?? ""
    persistDraft()
    render()
  }

  func paste(_ pasteboard: NSPasteboard) -> Bool {
    guard let rejections = model.attachments.add(pasteboard: pasteboard) else { return false }
    model.attachmentNotice = rejections.first?.message ?? ""
    persistDraft()
    render()
    return true
  }

  func removeAttachment(_ id: String) {
    model.attachments.remove(id: id)
    model.attachmentNotice = ""
    persistDraft()
    render()
  }

  @objc private func pickFiles() {
    service.pick(view.window) { [weak self] in self?.addFiles($0) }
  }

  func clearDraft() {
    draft.clear()
    if let sentId, let draftScope, let draftStore { try? draftStore.complete(draftScope, sendId: sentId) }
    sentId = nil
  }

  func textDidChange(_ notification: Notification) {
    model.text = view1.input.string
    persistDraft()
    render()
  }

  private func loadOptions() {
    optionsTask?.cancel()
    let workspaceId = model.form.workspaceId, projectId = model.form.chat ? nil : model.form.current.projectId
    let chat = model.form.chat
    let machineId = inheritedMachineId
    inheritedMachineId = nil
    optionsTask = Task { [weak self, service] in
      do {
        let options = try await service.options(workspaceId, projectId)
        guard !Task.isCancelled else { return }
        self?.model.form.applyOptions(options, chat: chat)
        if let self, let machineId, model.form.current.machines.contains(where: { $0.id == machineId }) {
          model.form.selectMachine(machineId)
        }
      } catch {
        guard !Task.isCancelled else { return }
        self?.model.form.failOptions(chat: chat)
      }
      self?.render()
    }
  }

  @objc private func projectChanged() {
    let index = view1.project.indexOfSelectedItem
    if index == model.form.projects.count {
      selectProject(nil)
    } else if model.form.projects.indices.contains(index) {
      selectProject(model.form.projects[index].id)
    }
  }

  @objc private func machineChanged() {
    let machines = model.form.current.machines
    guard machines.indices.contains(view1.machine.indexOfSelectedItem) else { return }
    configured = true
    model.form.selectMachine(machines[view1.machine.indexOfSelectedItem].id)
    persistDraft()
    render()
  }

  @objc private func agentChanged() {
    let agents = model.form.current.agents
    guard agents.indices.contains(view1.agent.indexOfSelectedItem) else { return }
    configured = true
    model.form.selectAgent(agents[view1.agent.indexOfSelectedItem].key)
    persistDraft()
    render()
  }

  @objc private func showOptions() {
    if optionsPopover.isShown { optionsPopover.performClose(nil); return }
    optionsPanel.render(model)
    let above: NSRectEdge = view1.modelPicker.isFlipped ? .minY : .maxY
    optionsPopover.show(relativeTo: view1.modelPicker.bounds, of: view1.modelPicker, preferredEdge: above)
  }

  @objc private func choiceChanged() {
    var choice = model.choice
    let modes = model.modes
    guard modes.indices.contains(view1.mode.indexOfSelectedItem) else { return }
    choice.modeId = modes[view1.mode.indexOfSelectedItem].id
    if model.mode == .newSession {
      configured = true
      model.form.updateChoice(choice)
    } else if let modeId = choice.modeId {
      onReplyChoice?(["permissionId": modeId])
    }
    render()
  }

  private func applyChoice(_ choice: ModelChoice) {
    if model.mode == .newSession {
      configured = true
      model.form.updateChoice(choice)
    } else {
      var body: [String: Any] = ["modelId": choice.modelId ?? "", "effort": choice.effort ?? ""]
      if let previous = CreateLogic.fastMode(model.capability, model.choice),
        let next = CreateLogic.fastMode(model.capability, choice), previous.enabled != next.enabled {
        body["fast"] = next.enabled
      }
      onReplyChoice?(body)
    }
    render()
  }

  private func send() {
    guard model.canSend else { return }
    let id = UUID().uuidString.lowercased()
    let text = model.text
    switch model.mode {
    case .newSession:
      guard let sessionId = model.form.current.options?.sessionId, let created = model.form.draft(sessionId: sessionId) else { return }
      guard handoff(id) else { return }
      let payload = model.payload(id: id)
      clearInput()
      onSend?()
      service.create(created, payload)
    case .reply:
      guard handoff(id) else { return }
      let payload = model.payload(id: id)
      draft.sent(text, attachments: model.attachments.items)
      clearInput()
      onSend?()
      service.reply(payload, model.replyChoice)
    }
  }

  private func clearInput() {
    view1.input.string = ""
    model.text = ""
    _ = model.attachments.take()
    model.attachmentNotice = ""
    render()
  }

  private func render() {
    guard isViewLoaded else { return }
    view1.render(model, reply: replyContext)
    optionsPanel.render(model)
    if model.models.isEmpty { optionsPopover.performClose(nil) }
  }
}
