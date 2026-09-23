import Foundation

/// Value state shared by the app's presentation host and the system extension.
struct CreateSessionForm {
  var snapshot: [String: Any] = [:]
  var discoveredProjects: [[String: Any]] = []
  var projectID = ""
  var chat = true
  var agentKey = ""
  var branch = ""
  var choice: [String: Any] = [:]
  var prefs: [String: Any] = [:]
  var configOptions: [[String: Any]] { capability["configOptions"] as? [[String: Any]] ?? [] }
  static func extraOption(_ option: [String: Any]) -> Bool {
    guard option["type"] as? String == "select" else { return true }
    return !["model", "mode", "thought_level"].contains(option["category"] as? String ?? "") && option["id"] as? String != "reasoning_effort"
  }
  var efforts: [String] {
    let model = choice["modelId"] as? String ?? configOptions.first { $0["category"] as? String == "model" }?["currentValue"] as? String ?? ""
    if let values = (capability["reasoningEfforts"] as? [String: [String]])?[model] { return values }
    return (configOptions.first { $0["category"] as? String == "thought_level" || $0["id"] as? String == "reasoning_effort" }?["options"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
  }
  private var modelKey: String { createJSON([agentKey, choice["modelId"] ?? NSNull()]) }
  mutating func selectModel(_ model: String?) {
    remember()
    choice = [:]
    if let model, !model.isEmpty { choice["modelId"] = model }
    restoreModel()
  }
  mutating func restoreModel(legacy: [String: Any] = [:]) {
    let model = choice["modelId"]
    let remembered = (prefs["modelChoices"] as? [String: [String: Any]])?[modelKey]
    choice = remembered ?? legacy
    choice["modelId"] = model
    if remembered == nil && choice["modeId"] == nil {
      choice["modeId"] = (capability["modes"] as? [[String: Any]] ?? []).first {
        ["agent-full-access", "danger-full-access", "bypassPermissions", "yolo", "always-approve"].contains($0["id"] as? String ?? "")
      }?["id"]
    }
    validateChoice()
  }
  var workspaceID: String { snapshot["workspaceId"] as? String ?? "" }
  var userID: String { snapshot["userId"] as? String ?? "" }
  var projects: [[String: Any]] {
    let cached = snapshot["projects"] as? [[String: Any]] ?? []
    return cached + discoveredProjects.filter { item in !cached.contains { $0["id"] as? String == item["id"] as? String } }
  }
  var project: [String: Any]? { projects.first { $0["id"] as? String == projectID } }
  var options: [String: Any] {
    let cached = snapshot["options"] as? [String: [String: Any]] ?? [:]
    return cached[chat ? "chat" : projectID] ?? cached["chat"] ?? [:]
  }
  var agents: [[String: Any]] {
    let all = options["agents"] as? [[String: Any]] ?? []
    if chat || projectID.hasPrefix("github:") { return all }
    return all.filter { $0["machineId"] as? String == project?["machineId"] as? String }
  }
  static func key(_ agent: [String: Any]) -> String {
    (agent["machineId"] as? String ?? "") + ":" + (agent["id"] as? String ?? "")
  }
  var agent: [String: Any]? { agents.first { Self.key($0) == agentKey } }
  var capability: [String: Any] {
    guard let agent else { return [:] }
    return (options["capabilities"] as? [[String: Any]] ?? []).first {
      $0["machineId"] as? String == agent["machineId"] as? String &&
      $0["cliType"] as? String == agent["cliType"] as? String &&
      $0["agentType"] as? String == agent["agentType"] as? String
    } ?? [:]
  }
  var canSend: Bool {
    !userID.isEmpty && !workspaceID.isEmpty && agent != nil &&
      (chat || project != nil) && (chat || !projectID.hasPrefix("github:") || !branch.trimmingCharacters(in: .whitespaces).isEmpty)
  }
  var modelSummary: String {
    var parts: [String] = []
    for (field, source) in [("modelId", "models"), ("modeId", "modes")] {
      if let id = choice[field] as? String, let name = (capability[source] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == id })?["name"] as? String { parts.append(name) }
      if field == "modelId", let effort = choice["effort"] as? String, !effort.isEmpty { parts.append(effort) }
    }
    for option in configOptions.filter(Self.extraOption) {
      guard let id = option["id"] as? String, let name = option["name"] as? String,
        let value = (choice["configOptionValues"] as? [String: Any])?[id] else { continue }
      if let flag = value as? Bool { parts.append(name + ": " + LodyStrings.text(flag ? "native.create.on" : "native.create.off")) }
      else if let value = value as? String { parts.append(name + ": " + value) }
    }
    return parts.isEmpty ? LodyStrings.text("native.create.default") : parts.joined(separator: " · ")
  }
  mutating func restore() {
    let target = chat ? "chat" : projectID
    let saved = (prefs["projects"] as? [String: [String: Any]])?[target] ?? [:]
    agentKey = saved["agentKey"] as? String ?? ""
    if agent == nil { agentKey = agents.first.map(Self.key) ?? "" }
    choice = saved.filter { ["modelId", "effort", "modeId", "configOptionValues"].contains($0.key) }
    restoreModel(legacy: choice)
  }
  mutating func validateChoice() {
    for (field, source) in [("modelId", "models"), ("modeId", "modes")] {
      if let selected = choice[field] as? String,
        !(capability[source] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == selected }) {
        choice[field] = nil
      }
    }
    if let effort = choice["effort"] as? String, !efforts.contains(effort) { choice["effort"] = nil }
    let saved = choice["configOptionValues"] as? [String: Any] ?? [:]
    var valid: [String: Any] = [:]
    for option in configOptions.filter(Self.extraOption) {
      guard let id = option["id"] as? String, let value = saved[id] else { continue }
      if option["type"] as? String == "boolean", value is Bool { valid[id] = value }
      else if let value = value as? String, (option["options"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == value }) { valid[id] = value }
    }
    choice["configOptionValues"] = valid
  }
  mutating func remember() {
    var targets = prefs["projects"] as? [String: [String: Any]] ?? [:]
    targets[chat ? "chat" : projectID] = choice.merging(["agentKey": agentKey, "machineId": agent?["machineId"] ?? ""]) { _, new in new }
    prefs["projects"] = targets
    var models = prefs["modelChoices"] as? [String: [String: Any]] ?? [:]
    models[modelKey] = choice; prefs["modelChoices"] = models
    prefs["context"] = chat ? "chat" : "project"
    if !chat { prefs["projectId"] = projectID }
  }
  func draft(_ payload: [String: Any]) -> [String: Any]? {
    guard canSend, let agent, let text = payload["text"] as? String else { return nil }
    var config = choice
    config["reasoningEffortConfigId"] = capability["reasoningEffortConfigId"]
    return payload.merging([
      "userId": userID, "workspaceId": workspaceID, "agent": agent, "choice": config,
      "sessionId": options["sessionId"] ?? "",
      "projectId": chat ? "" : projectID, "projectName": chat ? LodyStrings.text("native.create.chat") : (project?["name"] as? String ?? ""),
      "branch": branch, "title": String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)).isEmpty ? LodyStrings.text("native.create.title") : String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
    ]) { _, new in new }
  }
}

func createJSON(_ value: Any) -> String {
  guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
    let text = String(data: bytes, encoding: .utf8) else { return "{}" }
  return text
}
