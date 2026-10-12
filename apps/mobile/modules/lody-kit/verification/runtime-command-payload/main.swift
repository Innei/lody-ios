import Foundation

func json(_ object: [String: Any]) -> String {
  String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}
let small = "{}"
let providerValue = String(repeating: "界", count: 31_500)
let providerConfig: [String: Any] = ["id": "config", "machineId": "machine", "name": "Provider",
  "cliType": "builtin", "agentType": "codex", "env": ["A": providerValue, "B": providerValue, "C": providerValue, "D": providerValue]]
precondition(json(providerConfig).utf16.count <= 128 * 1024, "The Unicode config satisfies the runtime's serialized UTF-16 ceiling")
let provider = json(["workspaceId": "workspace", "machineId": "machine", "userId": "user",
  "action": "save", "config": providerConfig])
precondition(provider.utf8.count > 128 * 1024 && provider.utf8.count < 400 * 1024)
let providerArgs = RuntimeCommandPayload.decode(provider, method: "providerCommand")
let providerEnv = (providerArgs?["config"] as? [String: Any])?["env"] as? [String: String]
precondition(providerEnv?["A"] == providerValue && providerEnv?.count == 4, "A legal Unicode Provider envelope reaches runtime without changing its environment")
precondition(RuntimeCommandPayload.decode(provider, method: "checkSend") == nil)
let providerLimit = 400 * 1024
precondition(RuntimeCommandPayload.decode(small + String(repeating: " ", count: providerLimit - small.utf8.count), method: "providerCommand") != nil)
precondition(RuntimeCommandPayload.decode(small + String(repeating: " ", count: providerLimit - small.utf8.count + 1), method: "providerCommand") == nil)

let roleValue = String(repeating: "界", count: 512)
let roleOptions = Dictionary(uniqueKeysWithValues: (0..<64).map { (String(repeating: "界", count: 125) + String(format: "%03d", $0), roleValue) })
let role: [String: Any] = ["modelId": String(repeating: "界", count: 4096), "modeId": String(repeating: "界", count: 4096),
  "configOptionValues": roleOptions, "memory": ["providerId": String(repeating: "界", count: 100), "memoryId": String(repeating: "界", count: 200)]]
let turnId = "00000000-0000-4000-8000-000000000001"
let send = json(["workspaceId": "workspace", "sessionId": turnId, "id": turnId, "userId": "user", "machineId": "machine",
  "cliType": "builtin", "agentType": "codex", "text": String(repeating: "界", count: 32_000),
  "agentRoleId": "role", "agentRoleRevision": 1, "frozenRole": role, "configOptionValues": roleOptions])
precondition(send.utf8.count > 128 * 1024)
for method in ["sendTurn", "editSession", "checkTurnQuota"] {
  let turn = RuntimeCommandPayload.decode(send, method: method)
  let frozen = turn?["frozenRole"] as? [String: Any]
  precondition((frozen?["configOptionValues"] as? [String: String]) == roleOptions)
  precondition((turn?["configOptionValues"] as? [String: String]) == roleOptions, "Quota and send/edit preparation retain the entire Role choice")
}
let create = json(["workspaceId": "workspace", "sessionId": turnId, "title": "Session", "userId": "user", "machineId": "machine",
  "agentConfigId": "agent", "agentRoleId": "role", "agentRoleRevision": 1, "frozenRole": role])
precondition(create.utf8.count > 128 * 1024)
let creationRole = RuntimeCommandPayload.decode(create, method: "createSession")?["frozenRole"] as? [String: Any]
precondition((creationRole?["configOptionValues"] as? [String: String]) == roleOptions)

let queueText = String(repeating: "界", count: 32_000)
let queueEdit = json(["workspaceId": "workspace", "sessionId": turnId, "id": turnId,
  "action": "save-edit", "text": queueText, "baseText": queueText, "editingStartedAt": 1])
let edit = RuntimeCommandPayload.decode(queueEdit, method: "queueMessage")
precondition(edit?["text"] as? String == queueText && edit?["baseText"] as? String == queueText)
let order = (0..<10_000).map { String(format: "00000000-0000-4000-8000-%012d", $0) }
let queueCheck = json(["workspaceId": "workspace", "sessionId": turnId, "id": turnId, "action": "check",
  "receipt": ["id": turnId, "action": "move-up", "order": order]])
let receipt = RuntimeCommandPayload.decode(queueCheck, method: "queueMessage")?["receipt"] as? [String: Any]
precondition(receipt?["order"] as? [String] == order, "Queue confirmation preserves all ten thousand stable IDs")

for (method, bytes) in [
  ("queueMessage", 16 * 1024 * 1024), ("sendTurn", 2 * 1024 * 1024), ("editSession", 2 * 1024 * 1024),
  ("checkTurnQuota", 2 * 1024 * 1024), ("createSession", 2 * 1024 * 1024), ("checkSend", 128 * 1024)] {
  precondition(RuntimeCommandPayload.decode(small + String(repeating: " ", count: bytes - small.utf8.count), method: method) != nil)
  precondition(RuntimeCommandPayload.decode(small + String(repeating: " ", count: bytes - small.utf8.count + 1), method: method) == nil, "Every method retains a finite input ceiling")
}
