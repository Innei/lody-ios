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
  var onReplyChoice: (([String: Any]) -> Void)?
  var onSend: (() -> Void)?
  var replyContext: (project: String, branch: String, machine: String) = ("", "", "") {
    didSet { render() }
  }

  init(model: MacComposerModel, service: MacComposerService) {
    self.model = model
    self.service = service
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = view1
    view1.input.delegate = self
    view1.onSend = { [weak self] in self?.send() }
    view1.onDropFiles = { [weak self] in self?.addFiles($0) }
    view1.input.onDropFiles = { [weak self] in self?.addFiles($0) }
    view1.input.onPasteAttachments = { [weak self] in self?.paste($0) ?? false }
    view1.attach.target = self
    view1.attach.action = #selector(pickFiles)
    view1.strip.onRemove = { [weak self] in self?.removeAttachment($0.id) }
    view1.project.target = self
    view1.project.action = #selector(projectChanged)
    view1.machine.target = self
    view1.machine.action = #selector(machineChanged)
    view1.agent.target = self
    view1.agent.action = #selector(agentChanged)
    view1.mode.target = self
    view1.mode.action = #selector(choiceChanged)
    view1.modelPicker.target = self
    view1.modelPicker.action = #selector(choiceChanged)
    view1.effort.target = self
    view1.effort.action = #selector(choiceChanged)
    render()
    if model.mode == .newSession { loadOptions() }
  }

  func updateReply(ready: Bool, capability: Capability?, choice: ModelChoice?) {
    model.replyReady = ready
    model.replyCapability = capability
    if let choice { model.replyChoice = choice }
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
    render()
  }

  func addFiles(_ urls: [URL]) {
    let rejections = model.attachments.add(urls: urls)
    model.attachmentNotice = rejections.first?.message ?? ""
    render()
  }

  func paste(_ pasteboard: NSPasteboard) -> Bool {
    guard let rejections = model.attachments.add(pasteboard: pasteboard) else { return false }
    model.attachmentNotice = rejections.first?.message ?? ""
    render()
    return true
  }

  func removeAttachment(_ id: String) {
    model.attachments.remove(id: id)
    model.attachmentNotice = ""
    render()
  }

  @objc private func pickFiles() {
    service.pick(view.window) { [weak self] in self?.addFiles($0) }
  }

  func clearDraft() { draft.clear() }

  func textDidChange(_ notification: Notification) {
    model.text = view1.input.string
    render()
  }

  private func loadOptions() {
    optionsTask?.cancel()
    let workspaceId = model.form.workspaceId, projectId = model.form.chat ? nil : model.form.current.projectId
    let chat = model.form.chat
    optionsTask = Task { [weak self, service] in
      do {
        let options = try await service.options(workspaceId, projectId)
        guard !Task.isCancelled else { return }
        self?.model.form.applyOptions(options, chat: chat)
      } catch {
        self?.model.form.failOptions(chat: chat)
      }
      self?.render()
    }
  }

  @objc private func projectChanged() {
    let index = view1.project.indexOfSelectedItem
    if index == model.form.projects.count {
      model.form.switchPage(chat: true)
    } else if model.form.projects.indices.contains(index) {
      model.form.switchPage(chat: false)
      model.form.selectProject(model.form.projects[index])
    }
    render()
    loadOptions()
  }

  @objc private func machineChanged() {
    let machines = model.form.current.machines
    guard machines.indices.contains(view1.machine.indexOfSelectedItem) else { return }
    model.form.selectMachine(machines[view1.machine.indexOfSelectedItem].id)
    render()
  }

  @objc private func agentChanged() {
    let agents = model.form.current.agents
    guard agents.indices.contains(view1.agent.indexOfSelectedItem) else { return }
    model.form.selectAgent(agents[view1.agent.indexOfSelectedItem].key)
    render()
  }

  @objc private func choiceChanged() {
    var choice = model.choice
    let modes = model.modes, models = model.models, efforts = model.efforts
    if modes.indices.contains(view1.mode.indexOfSelectedItem) { choice.modeId = modes[view1.mode.indexOfSelectedItem].id }
    if models.indices.contains(view1.modelPicker.indexOfSelectedItem) { choice.modelId = models[view1.modelPicker.indexOfSelectedItem].id }
    if efforts.indices.contains(view1.effort.indexOfSelectedItem) { choice.effort = efforts[view1.effort.indexOfSelectedItem] }
    if model.mode == .newSession {
      model.form.updateChoice(choice)
    } else if choice.modeId != model.replyChoice.modeId, let modeId = choice.modeId {
      onReplyChoice?(["permissionId": modeId])
    } else {
      onReplyChoice?(["modelId": choice.modelId ?? "", "effort": choice.effort ?? ""])
    }
    render()
  }

  private func send() {
    guard model.canSend else { return }
    let payload = model.payload(id: UUID().uuidString.lowercased())
    let text = model.text
    switch model.mode {
    case .newSession:
      guard let sessionId = model.form.current.options?.sessionId, let created = model.form.draft(sessionId: sessionId) else { return }
      clearInput()
      service.create(created, payload)
    case .reply:
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
  }
}
