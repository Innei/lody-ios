import LodyCore
import Foundation

public struct CreateSessionPage: Equatable, Sendable {
  public let chat: Bool
  public var projectId = ""
  public var options: CreationOptions?
  public var machineId = ""
  public var agentKey = ""
  public var choice = ModelChoice()
  public var branch = ""
  public var branches: CreateBranches?
  public var branchesLoading = false
  public var branchesFailed = false
  public var loading = true
  public var failed = false

  public var target: String { chat ? CreateLogic.chatTarget : projectId }
  public var github: Bool { !chat && projectId.hasPrefix("github:") }

  // Local projects expose only their owning machine; GitHub projects and chats
  // can choose among the machines returned by the runtime.
  public var machines: [(id: String, name: String)] {
    var seen = Set<String>()
    return (options?.agents ?? []).compactMap { agent in
      seen.insert(agent.machineId).inserted ? (agent.machineId, agent.machineName) : nil
    }
  }
  public var machine: (id: String, name: String)? {
    if machineId.isEmpty { return machines.first }
    return machines.first { $0.id == machineId }
  }
  public var needsOptions: Bool { failed || options == nil || agent == nil }
  public var unavailableMessage: String? {
    if failed { return String(localized: "create.devices.failed", bundle: .lodyData) }
    if options?.availability == "unknown" { return String(localized: "devices.unknown", bundle: .lodyData) }
    if !machineId.isEmpty && machine == nil {
      return String(localized: String.LocalizationValue(!chat && !github ? "create.devices.projectOffline" : "create.devices.selectedOffline"), bundle: .lodyData)
    }
    if options?.availability == "offline" {
      return String(localized: String.LocalizationValue(!chat && !github ? "create.devices.projectOffline" : "create.devices.offline"), bundle: .lodyData)
    }
    if !agents.isEmpty && agent == nil { return String(localized: "create.devices.chooseAgent", bundle: .lodyData) }
    if options != nil && agent == nil { return String(localized: "create.devices.noAgents", bundle: .lodyData) }
    return nil
  }
  public var agents: [CreationAgent] { (options?.agents ?? []).filter { $0.machineId == machine?.id } }
  public var agent: CreationAgent? { agents.first { $0.key == agentKey } }
  public var capability: Capability? { CreateLogic.capabilityFor(options, agent) }

  public init(chat: Bool, projectId: String = "", options: CreationOptions? = nil, machineId: String = "", agentKey: String = "", choice: ModelChoice = ModelChoice(), branch: String = "", branches: CreateBranches? = nil, branchesLoading: Bool = false, branchesFailed: Bool = false, loading: Bool = true, failed: Bool = false) {
    self.chat = chat
    self.projectId = projectId
    self.options = options
    self.machineId = machineId
    self.agentKey = agentKey
    self.choice = choice
    self.branch = branch
    self.branches = branches
    self.branchesLoading = branchesLoading
    self.branchesFailed = branchesFailed
    self.loading = loading
    self.failed = failed
  }
}

public struct CreateSessionDraft: Codable, Equatable, Sendable {
  public var sessionId: String
  public var userId: String
  public var workspaceId: String
  public var projectId: String?
  public var projectName: String
  public var branch: String?
  public var agent: CreationAgent
  public var choice: ModelChoice
  public var reasoningEffortConfigId: String?

  public init(sessionId: String, userId: String, workspaceId: String, projectId: String? = nil, projectName: String, branch: String? = nil, agent: CreationAgent, choice: ModelChoice, reasoningEffortConfigId: String? = nil) {
    self.sessionId = sessionId
    self.userId = userId
    self.workspaceId = workspaceId
    self.projectId = projectId
    self.projectName = projectName
    self.branch = branch
    self.agent = agent
    self.choice = choice
    self.reasoningEffortConfigId = reasoningEffortConfigId
  }
}

public struct CreateSessionForm: Sendable {
  public var userId = ""
  public var workspaceId = ""
  public var projects: [CreateProject] = []
  public var machineNames: [String: String] = [:]
  public var prefs: CreatePrefs?
  public var locked = false
  // Share Extension: a selection without cached options is sent and finished in the app.
  public var deferUnresolved = false
  public var signedOut = false
  public var chat = false
  public var project = CreateSessionPage(chat: false)
  public var chatPage = CreateSessionPage(chat: true)

  public init(
    userId: String = "", workspaceId: String = "", projects: [CreateProject] = [], machineNames: [String: String] = [:],
    prefs: CreatePrefs? = nil, locked: Bool = false, deferUnresolved: Bool = false, signedOut: Bool = false, chat: Bool = false
  ) {
    self.userId = userId
    self.workspaceId = workspaceId
    self.projects = projects
    self.machineNames = machineNames
    self.prefs = prefs
    self.locked = locked
    self.deferUnresolved = deferUnresolved
    self.signedOut = signedOut
    self.chat = chat
  }

  public var current: CreateSessionPage {
    get { chat ? chatPage : project }
    set { if chat { chatPage = newValue } else { project = newValue } }
  }

  public var prefsTarget: String { current.target }

  public mutating func open(projectId: String?, context: String?) {
    chat = context == "chat"
    locked = projectId != nil && !chat
    project.projectId = projectId
      ?? CreateLogic.rememberedProject(prefs, projects)
      ?? projects.first?.id
      ?? ""
    if !locked { chatPage.loading = true }
    if project.projectId.isEmpty { project.loading = false }
  }

  public mutating func applyOptions(_ options: CreationOptions, chat: Bool) {
    var page = chat ? chatPage : project
    let previous = page
    page.options = options
    page.loading = false
    page.failed = false
    let restored = CreateLogic.restoreSelection(prefs, target: page.target, options: options)
    page.machineId = restored.machineId
    page.agentKey = restored.agentKey
    page.choice = restored.choice
    // Refreshing availability must never silently move a draft to another computer.
    if previous.options != nil && !previous.machineId.isEmpty {
      page.machineId = previous.machineId
      page.agentKey = previous.agentKey
      page.choice = previous.choice
      if let agent = page.agent {
        page.choice = CreateLogic.rememberedModelChoice(
          prefs, agentKey: agent.key, capability: page.capability, modelId: previous.choice.modelId)
      }
    }
    if chat { chatPage = page } else { project = page }
  }

  public mutating func failOptions(chat: Bool) {
    if chat {
      chatPage.loading = false
      chatPage.failed = true
    } else {
      project.loading = false
      project.failed = true
    }
  }

  public mutating func selectProject(_ picked: CreateProject) {
    if !projects.contains(where: { $0.id == picked.id }) { projects.append(picked) }
    guard picked.id != project.projectId else { return }
    project = CreateSessionPage(chat: false, projectId: picked.id)
  }

  public mutating func applyBranches(_ value: CreateBranches) {
    if project.branches == nil { project.branches = value }
    else { project.branches?.append(value) }
    project.branchesLoading = false
    project.branchesFailed = false
    if project.branch.isEmpty, let name = project.branches?.defaultBranch,
      project.branches?.names.contains(name) == true { project.branch = name }
  }

  public mutating func selectMachine(_ id: String) {
    current.machineId = id
    let first = current.options?.agents.first { $0.machineId == id }
    current.agentKey = first?.key ?? ""
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: first?.key ?? "", capability: CreateLogic.capabilityFor(current.options, first)))
  }

  public mutating func selectAgent(_ key: String) {
    current.agentKey = key
    let selected = current.options?.agents.first { $0.key == key }
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: key, capability: CreateLogic.capabilityFor(current.options, selected)))
  }

  public mutating func selectModel(_ modelId: String?) {
    updateChoice(CreateLogic.rememberedModelChoice(
      prefs, agentKey: current.agentKey, capability: current.capability, modelId: modelId))
  }

  public mutating func updateChoice(_ next: ModelChoice) {
    current.choice = next
    guard let agent = current.agent else { return }
    prefs = CreateLogic.withSelection(prefs, target: prefsTarget, selection: ProjectPrefs(
      modelId: next.modelId, effort: next.effort, modeId: next.modeId, configOptionValues: next.configOptionValues,
      machineId: agent.machineId, agentKey: agent.key), chat: chat)
  }

  public mutating func switchPage(chat next: Bool) {
    chat = next
    var value = prefs ?? CreatePrefs()
    value.context = next ? "chat" : "project"
    prefs = value
  }

  public var canSend: Bool {
    !userId.isEmpty && !current.loading &&
      (deferUnresolved || (!current.failed && current.agent != nil && (!current.github || !current.branch.isEmpty)))
  }

  public var notice: String {
    if signedOut { return "" }
    if !deferUnresolved, current.unavailableMessage != nil { return "" }
    if current.loading { return String(localized: "create.composer.loading", bundle: .lodyData) }
    if current.agent == nil {
      return String(localized: String.LocalizationValue(deferUnresolved ? "native.share.deferred" : "create.composer.needAgent"), bundle: .lodyData)
    }
    return ""
  }

  public func draft(sessionId: String) -> CreateSessionDraft? {
    let page = current
    guard let agent = page.agent, !userId.isEmpty, !page.github || !page.branch.isEmpty else { return nil }
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
