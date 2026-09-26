import Foundation

// Ports tests/sessions/create-prefs.test.mjs onto the production Swift form.
func check(_ condition: Bool, _ message: String) {
  if !condition { fatalError(message) }
}

func roundTrip(_ prefs: CreatePrefs?) -> CreatePrefs? {
  CreateJSON.decode(CreatePrefs.self, CreateJSON.encode(prefs))
}

let codex = CreationAgent(id: "c1", name: "A", machineId: "m1", machineName: "Mac", cliType: "builtin", agentType: "codex")
let claude = CreationAgent(id: "c2", name: "B", machineId: "m2", machineName: "PC", cliType: "builtin", agentType: "claude")
let claudeCapability = Capability(
  machineId: "m2", cliType: "builtin", agentType: "claude",
  models: [CapabilityChoice(id: "opus", name: "Opus")], modes: [CapabilityChoice(id: "plan", name: "Plan")],
  reasoningEfforts: ["opus": ["low", "high"]])
let options = CreationOptions(sessionId: "s", project: CreateProject(id: "p1", machineId: "m1", name: "P"), agents: [codex, claude], capabilities: [claudeCapability])

// Chat context is remembered without overwriting the last project.
do {
  let project = CreateLogic.withSelection(nil, target: "p1", selection: ProjectPrefs(machineId: "m1", agentKey: "m1:c1"), chat: false)
  let chat = CreateLogic.withSelection(project, target: "chat", selection: ProjectPrefs(machineId: "m2", agentKey: "m2:c2"), chat: true)
  check(chat.context == "chat", "chat context")
  check(chat.projectId == "p1", "chat keeps project")
  check(CreateLogic.restoreSelection(chat, target: "chat", options: options).agentKey == "m2:c2", "chat agent restored")
}

// The sheet opens on the project page unless chat is requested.
do {
  var form = CreateSessionForm(projects: [CreateProject(id: "p1", machineId: "m1", name: "P")], prefs: CreatePrefs(context: "chat"))
  form.open(projectId: nil, context: nil)
  check(!form.chat && !form.locked, "project page opens by default")
  form.open(projectId: "p1", context: nil)
  check(form.locked, "an explicit project locks the sheet")
  form.open(projectId: nil, context: "chat")
  check(form.chat && !form.locked, "chat context")
}

// Remembered agent and model per project, dropping choices the machine no longer offers.
do {
  let prefs = CreateLogic.withSelection(CreatePrefs(projectId: "old"), target: "p1", selection: ProjectPrefs(
    modelId: "opus", effort: "high", modeId: "plan", machineId: "m2", agentKey: "m2:c2"), chat: false)
  check(prefs.projectId == "p1", "project remembered")
  check(CreateLogic.rememberedProject(prefs, [CreateProject(id: "p1", machineId: "m1", name: "P")]) == "p1", "project found")
  check(CreateLogic.rememberedProject(prefs, [CreateProject(id: "p9", machineId: "m1", name: "Gone")]) == nil, "missing project")
  let restored = CreateLogic.restoreSelection(prefs, target: "p1", options: options)
  check(restored.machineId == "m2" && restored.agentKey == "m2:c2", "agent restored")
  check(restored.choice == ModelChoice(modelId: "opus", effort: "high", modeId: "plan"), "choice restored")
  let stale = CreateLogic.withSelection(prefs, target: "p1", selection: ProjectPrefs(
    modelId: "gone", effort: "high", modeId: "plan", machineId: "m2", agentKey: "m2:removed"), chat: false)
  let fallback = CreateLogic.restoreSelection(stale, target: "p1", options: options)
  check(fallback.agentKey == "m2:c2" && fallback.choice == ModelChoice(), "stale choices dropped")
  let empty = CreateLogic.restoreSelection(nil, target: "p1", options: options)
  check(empty.agentKey == "m1:c1" && empty.choice == ModelChoice(), "first agent by default")
  check(CreateLogic.restoreSelection(prefs, target: "other", options: options).agentKey == "m1:c1", "per project")
}

// Each model is remembered across projects and serialization, without leaking agent choices.
do {
  var capability = claudeCapability
  capability.models = [CapabilityChoice(id: "opus", name: ""), CapabilityChoice(id: "sonnet", name: "")]
  capability.modes = [CapabilityChoice(id: "plan", name: ""), CapabilityChoice(id: "bypassPermissions", name: "")]
  capability.reasoningEfforts = ["opus": ["low", "high"], "sonnet": ["low", "high"]]
  var prefs = CreateLogic.withSelection(nil, target: "p1", selection: ProjectPrefs(modelId: "opus", effort: "high", modeId: "plan", agentKey: "m2:c2"), chat: false)
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "m2:c2", capability: capability, modelId: "sonnet")
    == ModelChoice(modelId: "sonnet", modeId: "bypassPermissions"), "new model defaults to full access")
  prefs = roundTrip(CreateLogic.withSelection(prefs, target: "p2", selection: ProjectPrefs(modelId: "sonnet", effort: "low", modeId: "bypassPermissions", agentKey: "m2:c2"), chat: false))!
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "m2:c2", capability: capability, modelId: "opus")
    == ModelChoice(modelId: "opus", effort: "high", modeId: "plan"), "model memory survives JSON")
  let other = CreateLogic.rememberedModelChoice(prefs, agentKey: "another-agent", capability: capability, modelId: "opus")
  check(other.modeId == "bypassPermissions" && other.effort == nil, "no leak across agents")
  var removed = capability
  removed.reasoningEfforts = [:]
  removed.modes = [CapabilityChoice(id: "bypassPermissions", name: "")]
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "m2:c2", capability: removed, modelId: "opus")
    == ModelChoice(modelId: "opus", modeId: "bypassPermissions"), "removed effort and mode dropped")
  prefs = CreateLogic.withSelection(prefs, target: "p1", selection: ProjectPrefs(modelId: "opus", agentKey: "m2:c2"), chat: false)
  check(CreateLogic.rememberedModelChoice(roundTrip(prefs), agentKey: "m2:c2", capability: capability, modelId: "opus").modeId == nil,
    "explicit assistant default is remembered")
}

// Full access defaults only use modes the assistant offers; legacy project prefs still restore.
do {
  for id in CreateLogic.fullAccessModes {
    var capability = claudeCapability
    capability.modes = [CapabilityChoice(id: "plan", name: ""), CapabilityChoice(id: id, name: "")]
    check(CreateLogic.rememberedModelChoice(nil, agentKey: "agent", capability: capability).modeId == id, "full access \(id)")
  }
  check(CreateLogic.rememberedModelChoice(nil, agentKey: "agent", capability: claudeCapability).modeId == nil, "no full access mode")
  let legacy = CreatePrefs(projects: ["p1": ProjectPrefs(modelId: "opus", effort: "high", modeId: "plan", agentKey: "m2:c2")])
  check(CreateLogic.restoreSelection(legacy, target: "p1", options: options).choice.modeId == "plan", "legacy prefs")
}

// Permission, boolean and custom choices survive serialization, scoped to agent and model.
do {
  func select(_ id: String, _ values: [String], _ category: String? = nil) -> ConfigOption {
    ConfigOption(id: id, name: id, category: category ?? id, type: "select", options: values.map { CapabilityChoice(id: $0, name: $0) })
  }
  var capability = claudeCapability
  capability.reasoningEfforts = [:]
  capability.configOptions = [
    select("permission_mode", ["ask", "always-approve"], "_permission"),
    ConfigOption(id: "fast", name: "fast", type: "boolean"),
    select("agent_preset", ["standard", "coder"]),
    select("effort", ["low", "high"], "thought_level"),
  ]
  let values: [String: ConfigValue] = ["permission_mode": .string("always-approve"), "fast": .bool(false), "agent_preset": .string("coder")]
  var prefs = CreateLogic.withSelection(nil, target: "p1", selection: ProjectPrefs(modelId: "a", effort: "high", configOptionValues: values, agentKey: "grok"), chat: false)
  prefs = roundTrip(CreateLogic.withSelection(prefs, target: "p2", selection: ProjectPrefs(modelId: "b", configOptionValues: ["permission_mode": .string("ask")], agentKey: "grok"), chat: false))!
  let restored = CreateLogic.rememberedModelChoice(prefs, agentKey: "grok", capability: capability, modelId: "a")
  check(restored.configOptionValues == values, "config values survive JSON")
  check(restored.effort == "high", "config-only effort")
  check(CreateLogic.effortsFor(capability, modelId: "a") == ["low", "high"], "thought level efforts")
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "other-agent", capability: capability, modelId: "a").configOptionValues == nil, "scoped to agent")
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "grok", capability: capability, modelId: "c").configOptionValues == nil, "scoped to model")
  var changed = capability
  changed.configOptions = [select("permission_mode", ["ask"]), select("fast", ["on", "off"])]
  check(CreateLogic.rememberedModelChoice(prefs, agentKey: "grok", capability: changed, modelId: "a").configOptionValues == nil,
    "removed values and changed option types are discarded")
  prefs = CreateLogic.withSelection(prefs, target: "p1", selection: ProjectPrefs(modelId: "a", configOptionValues: [:], agentKey: "grok"), chat: false)
  check(CreateLogic.rememberedModelChoice(roundTrip(prefs), agentKey: "grok", capability: capability, modelId: "a").configOptionValues == nil,
    "Use default clears the remembered override")
}

// Prefs written by the RN page (JSON.stringify) decode and restore unchanged.
do {
  let written = #"{"projectId":"p1","context":"project","modelChoices":{"[\"m2:c2\",\"opus\"]":{"modelId":"opus","effort":"high","modeId":"plan","configOptionValues":{"fast":true}}},"projects":{"p1":{"machineId":"m2","agentKey":"m2:c2","modelId":"opus","effort":"high","modeId":"plan"}}}"#
  let prefs = CreateJSON.decode(CreatePrefs.self, written)
  check(prefs?.projects?["p1"]?.agentKey == "m2:c2", "RN prefs decode")
  check(prefs?.modelChoices?[CreateLogic.modelKey("m2:c2", "opus")]?.configOptionValues?["fast"] == .bool(true), "model key matches JSON.stringify")
  check(CreateLogic.modelKey("m2:c2", nil) == #"["m2:c2",null]"#, "null model key")
  check(CreateLogic.modelKey("a/b", "x") == #"["a/b","x"]"#, "slashes are not escaped")
}

// The form builds a draft only for a ready agent, with branch and chat project rules.
do {
  let github = CreateProject(id: "github:Owner/Repo", machineId: "", name: "Owner/Repo")
  var form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [github])
  form.open(projectId: nil, context: nil)
  check(form.draft(sessionId: "s1") == nil, "no draft before options")
  form.applyOptions(options, chat: false)
  form.project.branch = " main "
  let draft = form.draft(sessionId: "s1")
  check(draft?.projectId == github.id && draft?.branch == "main" && draft?.agent == codex, "github draft")
  form.switchPage(chat: true)
  form.applyOptions(options, chat: true)
  let chat = form.draft(sessionId: "s2")
  check(chat?.projectId == nil && chat?.branch == nil && chat?.projectName == "", "chat draft")
  check(form.prefs?.context == "chat", "page switch remembered")
}
print("PASS: create-session form logic")
