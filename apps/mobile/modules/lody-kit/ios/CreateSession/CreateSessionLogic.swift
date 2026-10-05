import Foundation

enum CreateLogic {
  static let chatTarget = "chat"
  static let fullAccessModes = ["agent-full-access", "danger-full-access", "bypassPermissions", "yolo", "always-approve"]

  static func isThoughtLevel(_ option: ConfigOption) -> Bool {
    option.type == "select" && (option.category == "thought_level" || option.id == "reasoning_effort")
  }

  static func extraConfigOptions(_ capability: Capability?) -> [ConfigOption] {
    (capability?.configOptions ?? []).filter { option in
      !(option.type == "select" && ["model", "mode"].contains(option.category ?? "")) && !isThoughtLevel(option)
    }
  }

  static func validConfigValue(_ option: ConfigOption, _ value: ConfigValue?) -> Bool {
    switch value {
    case .bool: option.type == "boolean"
    case .string(let id): option.type != "boolean" && option.options.contains { $0.id == id }
    case nil: false
    }
  }

  static func effortsFor(_ capability: Capability?, modelId: String? = nil) -> [String] {
    var model = modelId
    if model == nil, case .string(let current)? = capability?.configOptions?.first(where: { $0.category == "model" })?.currentValue {
      model = current
    }
    if let model, let efforts = capability?.reasoningEfforts[model] { return efforts }
    return capability?.configOptions?.first(where: isThoughtLevel)?.options.map(\.id) ?? []
  }

  static func capabilityFor(_ options: CreationOptions?, _ agent: CreationAgent?) -> Capability? {
    guard let options, let agent else { return nil }
    return options.capabilities.first {
      $0.machineId == agent.machineId && $0.cliType == agent.cliType && $0.agentType == agent.agentType
    }
  }

  static func fastMode(_ capability: Capability?, _ choice: ModelChoice) -> (id: String, enabled: Bool)? {
    guard let option = capability?.configOptions?.first(where: { ["fast-mode", "fast"].contains($0.id) && $0.type == "boolean" })
    else { return nil }
    let value = choice.configOptionValues?[option.id] ?? option.currentValue
    return (option.id, value == .bool(true))
  }

  static func withFastMode(_ capability: Capability?, _ choice: ModelChoice, enabled: Bool) -> ModelChoice {
    guard let mode = fastMode(capability, choice) else { return choice }
    var next = choice
    next.configOptionValues = (choice.configOptionValues ?? [:]).merging([mode.id: .bool(enabled)]) { $1 }
    return next
  }

  // Same precedence as OSS resolvePermissionModeFace and the chat projection.
  static func permissionMode(_ capability: Capability?, _ choice: ModelChoice)
    -> (options: [CapabilityChoice], value: String?, configId: String?)?
  {
    let selectors = (capability?.configOptions ?? []).filter { $0.type == "select" }
    var option = selectors.first { $0.id == "permission_mode" || $0.category == "_permission" }
    if option == nil, let modes = capability?.legacyModes ?? capability?.modes, !modes.isEmpty {
      return (modes, choice.modeId, nil)
    }
    if option == nil {
      option = selectors.first { $0.category == "mode" && $0.id != "interaction_mode" && !isThoughtLevel($0) }
    }
    guard let option, !option.options.isEmpty else { return nil }
    let selected = choice.configOptionValues?[option.id]
    let current = validConfigValue(option, selected) ? selected : option.currentValue
    var value: String?
    if case .string(let id) = current { value = id }
    return (option.options, value, option.id)
  }

  static func withPermissionMode(_ capability: Capability?, _ choice: ModelChoice, value: String) -> ModelChoice {
    guard let permission = permissionMode(capability, choice), permission.options.contains(where: { $0.id == value }) else { return choice }
    var next = choice
    if let id = permission.configId {
      next.configOptionValues = (choice.configOptionValues ?? [:]).merging([id: .string(value)]) { $1 }
    } else {
      next.modeId = value
    }
    return next
  }

  static func rememberedProject(_ prefs: CreatePrefs?, _ projects: [CreateProject]) -> String? {
    projects.first { $0.id == prefs?.projectId }?.id
  }

  static func modelKey(_ agentKey: String, _ modelId: String?) -> String {
    CreateJSON.encode([agentKey, modelId].map { $0.map(JSONScalar.string) ?? .null })
  }

  static func restoreSelection(_ prefs: CreatePrefs?, target: String, options: CreationOptions)
    -> (machineId: String, agentKey: String, choice: ModelChoice)
  {
    let saved = prefs?.projects?[target] ?? ProjectPrefs()
    let agent = options.agents.first { $0.key == saved.agentKey }
      ?? options.agents.first { $0.machineId == saved.machineId }
      ?? options.agents.first
    let capability = capabilityFor(options, agent)
    let modelId = capability?.models.contains { $0.id == saved.modelId } == true ? saved.modelId : nil
    return (
      agent?.machineId ?? "",
      agent?.key ?? "",
      rememberedModelChoice(prefs, agentKey: agent?.key ?? "", capability: capability, modelId: modelId, legacy: saved)
    )
  }

  static func rememberedModelChoice(
    _ prefs: CreatePrefs?, agentKey: String, capability: Capability?, modelId: String? = nil, legacy: ProjectPrefs? = nil
  ) -> ModelChoice {
    let remembered = prefs?.modelChoices?[modelKey(agentKey, modelId)]
    let saved = remembered ?? (legacy?.agentKey == agentKey && legacy?.modelId == modelId ? legacy?.choice : nil)
    let effort = saved?.effort.flatMap { effortsFor(capability, modelId: modelId).contains($0) ? $0 : nil }
    var modeId = saved?.modeId
    if (remembered == nil && modeId == nil) || (modeId != nil && capability?.modes.contains { $0.id == modeId } != true) {
      modeId = capability?.modes.first { fullAccessModes.contains($0.id) }?.id
    }
    var values: [String: ConfigValue] = [:]
    // Mode config values selected by the composer must survive reopening too.
    for option in capability?.configOptions ?? [] where option.category != "model" && !isThoughtLevel(option) {
      let value = saved?.configOptionValues?[option.id]
      if validConfigValue(option, value) { values[option.id] = value }
    }
    return ModelChoice(modelId: modelId, effort: effort, modeId: modeId, configOptionValues: values.isEmpty ? nil : values)
  }

  static func withSelection(_ prefs: CreatePrefs?, target: String, selection: ProjectPrefs, chat: Bool) -> CreatePrefs {
    var next = prefs ?? CreatePrefs()
    next.context = chat ? "chat" : "project"
    if !chat { next.projectId = target }
    var models = next.modelChoices ?? [:]
    models[modelKey(selection.agentKey ?? "", selection.modelId)] = selection.choice
    next.modelChoices = models
    var projects = next.projects ?? [:]
    projects[target] = selection
    next.projects = projects
    return next
  }
}

enum JSONScalar: Encodable {
  case string(String)
  case null

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}
