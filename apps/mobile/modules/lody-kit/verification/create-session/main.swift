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
print("PASS: native form scopes machines, remembers per-model options including false, validates stale choices, requires GitHub branch and preserves attachments")
