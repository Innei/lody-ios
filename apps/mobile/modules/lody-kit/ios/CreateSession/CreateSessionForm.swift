import Foundation

struct CreateSessionPage: Equatable {
  let chat: Bool
  var projectId = ""
  var options: CreationOptions?
  var machineId = ""
  var agentKey = ""
  var choice = ModelChoice()
  var branch = ""
  var loading = true
  var failed = false

  var target: String { chat ? CreateLogic.chatTarget : projectId }
  var github: Bool { !chat && projectId.hasPrefix("github:") }

  // Local projects expose only their owning machine; GitHub projects and chats
  // can choose among the machines returned by the runtime.
  var machines: [(id: String, name: String)] {
    var seen = Set<String>()
    return (options?.agents ?? []).compactMap { agent in
      seen.insert(agent.machineId).inserted ? (agent.machineId, agent.machineName) : nil
    }
  }
  var machine: (id: String, name: String)? { machines.first { $0.id == machineId } ?? machines.first }
  var agents: [CreationAgent] { (options?.agents ?? []).filter { $0.machineId == machine?.id } }
  var agent: CreationAgent? { agents.first { $0.key == agentKey } }
  var capability: Capability? { CreateLogic.capabilityFor(options, agent) }
}

struct CreateSessionDraft: Codable, Equatable {
  var sessionId: String
  var userId: String
  var workspaceId: String
  var projectId: String?
  var projectName: String
  var branch: String?
  var agent: CreationAgent
  var choice: ModelChoice
  var reasoningEffortConfigId: String?
}

struct CreateSessionForm {
  var userId = ""
  var workspaceId = ""
  var projects: [CreateProject] = []
  var machineNames: [String: String] = [:]
  var prefs: CreatePrefs?
  var locked = false
  // Share Extension: a selection without cached options is sent and finished in the app.
  var deferUnresolved = false
  var signedOut = false
  var chat = false
  var project = CreateSessionPage(chat: false)
  var chatPage = CreateSessionPage(chat: true)

  var current: CreateSessionPage {
    get { chat ? chatPage : project }
    set { if chat { chatPage = newValue } else { project = newValue } }
  }

  var prefsTarget: String { current.target }

  mutating func open(projectId: String?, context: String?) {
    chat = context == "chat"
    locked = projectId != nil && !chat
    project.projectId = projectId
      ?? CreateLogic.rememberedProject(prefs, projects)
      ?? projects.first?.id
      ?? ""
    if !locked { chatPage.loading = true }
    if project.projectId.isEmpty { project.loading = false }
  }

  mutating func applyOptions(_ options: CreationOptions, chat: Bool) {
    var page = chat ? chatPage : project
    page.options = options
    page.loading = false
    page.failed = false
    let restored = CreateLogic.restoreSelection(prefs, target: page.target, options: options)
    page.machineId = restored.machineId
    page.agentKey = restored.agentKey
    page.choice = restored.choice
    if chat { chatPage = page } else { project = page }
  }

  mutating func failOptions(chat: Bool) {
    if chat {
      chatPage.loading = false
      chatPage.failed = true
    } else {
      project.loading = false
      project.failed = true
    }
  }

  mutating func selectProject(_ picked: CreateProject) {
    if !projects.contains(where: { $0.id == picked.id }) { projects.append(picked) }
    guard picked.id != project.projectId else { return }
    project = CreateSessionPage(chat: false, projectId: picked.id)
  }

  mutating func selectMachine(_ id: String) {
    current.machineId = id
    let first = current.options?.agents.first { $0.machineId == id }
    current.agentKey = first?.key ?? ""
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: first?.key ?? "", capability: CreateLogic.capabilityFor(current.options, first)))
  }

  mutating func selectAgent(_ key: String) {
    current.agentKey = key
    let selected = current.options?.agents.first { $0.key == key }
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: key, capability: CreateLogic.capabilityFor(current.options, selected)))
  }

  mutating func selectModel(_ modelId: String?) {
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: current.agentKey, capability: current.capability, modelId: modelId))
  }

  mutating func updateChoice(_ next: ModelChoice) {
    current.choice = next
    guard let agent = current.agent else { return }
    prefs = CreateLogic.withSelection(prefs, target: prefsTarget, selection: ProjectPrefs(
      modelId: next.modelId, effort: next.effort, modeId: next.modeId, configOptionValues: next.configOptionValues,
      machineId: agent.machineId, agentKey: agent.key), chat: chat)
  }

  mutating func switchPage(chat next: Bool) {
    chat = next
    var value = prefs ?? CreatePrefs()
    value.context = next ? "chat" : "project"
    prefs = value
  }

  var canSend: Bool { !userId.isEmpty && !current.loading && (current.agent != nil || deferUnresolved) }

  var notice: String {
    if signedOut { return "" }
    if current.loading { return LodyStrings.text("create.composer.loading") }
    if current.agent == nil {
      return LodyStrings.text(deferUnresolved ? "native.share.deferred" : "create.composer.needAgent")
    }
    return ""
  }

  func draft(sessionId: String) -> CreateSessionDraft? {
    let page = current
    guard let agent = page.agent, !userId.isEmpty else { return nil }
    let project = projects.first { $0.id == page.projectId }
    return CreateSessionDraft(
      sessionId: sessionId,
      userId: userId,
      workspaceId: workspaceId,
      projectId: page.chat ? nil : page.projectId,
      projectName: page.chat ? "" : (project?.name ?? page.options?.project?.name ?? ""),
      branch: page.github ? page.branch.trimmingCharacters(in: .whitespaces) : nil,
      agent: agent,
      choice: page.choice,
      reasoningEffortConfigId: page.capability?.reasoningEffortConfigId
    )
  }
}
