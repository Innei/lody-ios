import Foundation

let agents: [[String: Any]] = [
  ["id": "agent", "machineId": "one", "name": "Agent", "cliType": "builtin", "agentType": "codex"],
  ["id": "agent", "machineId": "two", "name": "Other", "cliType": "builtin", "agentType": "codex"],
]
let capability: [String: Any] = [
  "machineId": "one", "cliType": "builtin", "agentType": "codex",
  "models": [["id": "a", "name": "A"], ["id": "b", "name": "B"]],
  "modes": [["id": "read-only", "name": "Read Only"], ["id": "danger-full-access", "name": "Full Access"]],
  "reasoningEfforts": ["a": ["low", "high"], "b": ["low"]],
  "configOptions": [["id": "fast-mode", "type": "boolean"],
    ["id": "collaboration_mode", "type": "select", "options": [["id": "plan"], ["id": "default"]]]],
]
var form = CreateSessionForm()
form.snapshot = ["userId": "user", "workspaceId": "workspace",
  "projects": [["id": "one:local:project", "name": "Project", "machineId": "one"],
    ["id": "github:owner/repo", "name": "Repo", "machineId": ""]],
  "options": ["chat": ["sessionId": "reserved", "agents": agents, "capabilities": [capability]]]]
form.chat = false; form.projectID = "one:local:project"; form.restore()
precondition(form.agents.count == 1 && form.agentKey == "one:agent")
precondition(form.canSend)
form.selectModel("a"); form.choice["effort"] = "high"; form.choice["modeId"] = "read-only"
form.choice["configOptionValues"] = ["fast-mode": false, "collaboration_mode": "plan"]
form.selectModel("b")
precondition(form.choice["effort"] == nil)
precondition(form.choice["modeId"] as? String == "danger-full-access")
form.choice["effort"] = "low"
form.selectModel("a")
precondition(form.choice["effort"] as? String == "high")
precondition(form.choice["modeId"] as? String == "read-only")
precondition((form.choice["configOptionValues"] as? [String: Any])?["fast-mode"] as? Bool == false)
form.remember()
var restored = CreateSessionForm(); restored.snapshot = form.snapshot; restored.prefs = form.prefs
restored.chat = false; restored.projectID = form.projectID; restored.restore()
precondition(restored.choice["effort"] as? String == "high")
precondition(restored.agentKey == form.agentKey)
let draft = restored.draft(["id": "turn", "text": "Hello", "attachments": [["id": "file"]]])!
precondition(draft["sessionId"] as? String == "reserved")
precondition(draft["projectId"] as? String == "one:local:project")
precondition((draft["attachments"] as? [[String: String]])?.first?["id"] == "file")
restored.projectID = "github:owner/repo"; restored.restore()
precondition(!restored.canSend)
restored.branch = "main"; precondition(restored.canSend)
restored.chat = true; restored.restore(); precondition(restored.agents.count == 2)
precondition(restored.draft(["text": "Chat"])?["projectId"] as? String == "")
restored.choice = ["modelId": "deleted", "effort": "invalid", "modeId": "deleted", "configOptionValues": ["fast-mode": "true", "unknown": true]]
restored.validateChoice()
precondition(restored.choice["modelId"] == nil && restored.choice["effort"] == nil && restored.choice["modeId"] == nil)
precondition((restored.choice["configOptionValues"] as? [String: Any])?.isEmpty == true)
// Exercise the production owner, not the retired TypeScript preference replica.
func roundTrip(_ value: [String: Any]) -> [String: Any] {
  try! JSONSerialization.jsonObject(with: Data(createJSON(value).utf8)) as! [String: Any]
}
@MainActor func fixture(_ value: [String: Any] = capability) -> CreateSessionForm {
  var result = CreateSessionForm()
  result.snapshot = form.snapshot
  var second = value; second["machineId"] = "two"
  result.snapshot["options"] = ["chat": ["agents": agents, "capabilities": [value, second]]]
  result.restore()
  return result
}

var contexts = form
contexts.chat = true; contexts.agentKey = "two:agent"; contexts.choice = [:]; contexts.remember()
precondition(contexts.prefs["projectId"] as? String == "one:local:project", "Chat must not replace the last project")
contexts.prefs = roundTrip(contexts.prefs); contexts.restore()
precondition(contexts.agentKey == "two:agent")
contexts.chat = false; contexts.restore()
precondition(contexts.agentKey == "one:agent" && contexts.choice["effort"] as? String == "high")

var memory = fixture()
memory.prefs = roundTrip(form.prefs); memory.selectModel("a")
precondition(memory.choice["effort"] as? String == "high", "Model choices survive JSON and project-to-chat switching")
memory.agentKey = "two:agent"; memory.choice = ["modelId": "a"]; memory.restoreModel()
precondition(memory.choice["effort"] == nil, "Another machine/agent must not inherit the choice")
precondition(memory.choice["modeId"] as? String == "danger-full-access")

var legacy = form
legacy.prefs["modelChoices"] = nil; legacy.restore()
precondition(legacy.choice["effort"] as? String == "high" && legacy.choice["modeId"] as? String == "read-only")
legacy.choice["modeId"] = nil; legacy.choice["configOptionValues"] = [:]; legacy.remember()
legacy.prefs = roundTrip(legacy.prefs); legacy.restore()
precondition(legacy.choice["modeId"] == nil, "An explicit default must not turn back into full access")
precondition((legacy.choice["configOptionValues"] as? [String: Any])?.isEmpty == true)

for mode in ["agent-full-access", "danger-full-access", "bypassPermissions", "yolo", "always-approve"] {
  var advertised = capability; advertised["modes"] = [["id": "plan"], ["id": mode]]
  precondition(fixture(advertised).choice["modeId"] as? String == mode)
}
var noFullAccess = capability; noFullAccess["modes"] = [["id": "plan"]]
precondition(fixture(noFullAccess).choice["modeId"] == nil, "Never invent an unadvertised permission")

func select(_ id: String, _ values: [String], category: String = "") -> [String: Any] {
  ["id": id, "name": id, "type": "select", "category": category, "options": values.map { ["id": $0] }]
}
var configOnly = capability
configOnly["reasoningEfforts"] = [:]
configOnly["configOptions"] = [
  select("permission_mode", ["ask", "always-approve"], category: "_permission"),
  ["id": "fast", "type": "boolean"], select("agent_preset", ["standard", "coder"]),
  select("effort", ["low", "high"], category: "thought_level"),
]
var configured = fixture(configOnly)
configured.selectModel("a"); configured.choice["effort"] = "high"
configured.choice["configOptionValues"] = ["permission_mode": "always-approve", "fast": false, "agent_preset": "coder"]
configured.selectModel("b"); configured.prefs = roundTrip(configured.prefs); configured.selectModel("a")
let values = configured.choice["configOptionValues"] as! [String: Any]
precondition(values["permission_mode"] as? String == "always-approve")
precondition(values["fast"] as? Bool == false && values["agent_preset"] as? String == "coder")
precondition(configured.efforts == ["low", "high"] && configured.choice["effort"] as? String == "high")
var changed = configOnly
changed["configOptions"] = [select("permission_mode", ["ask"]), select("fast", ["on", "off"])]
var changedForm = fixture(changed); changedForm.prefs = configured.prefs; changedForm.selectModel("a")
precondition((changedForm.choice["configOptionValues"] as? [String: Any])?.isEmpty == true)
precondition(changedForm.choice["effort"] == nil, "Removed capabilities and changed option types must drop stale values")
print("PASS: production native form covers project/chat and agent isolation, JSON/legacy preferences, explicit defaults, model/config memory, stale capabilities and attachment draft handoff")
