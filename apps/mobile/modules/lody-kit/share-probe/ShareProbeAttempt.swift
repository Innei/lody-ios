import Foundation

struct ShareProbeAgent: Codable {
  let id: String
  let name: String
  let machineId: String
  let machineName: String
  let cliType: String
  let agentType: String
}

/// A receipt, never a replay queue. An interrupted attempt must be inspected in Lody.
struct ShareProbeAttempt: Codable {
  enum Phase: String, Codable {
    case prepared, creating, created, sending, accepted, uploaded, unknown, failed
  }

  let sessionId: String
  let sendId: String
  let userId: String
  let workspaceId: String
  let agent: ShareProbeAgent
  let text: String
  let createdAt: Date
  private(set) var phase: Phase = .prepared

  init(userId: String, workspaceId: String, agent: ShareProbeAgent, text: String) {
    sessionId = UUID().uuidString
    sendId = UUID().uuidString
    self.userId = userId
    self.workspaceId = workspaceId
    self.agent = agent
    self.text = text
    createdAt = Date()
  }

  @MainActor
  mutating func submit(
    command: (String, [String: Any]) async throws -> [String: Any],
    persist: (Self) throws -> Void
  ) async throws -> Phase {
    guard phase == .prepared, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 64 * 1024 else {
      throw NSError(domain: "LodyShareProbe", code: 1)
    }
    do {
      phase = .creating
      try persist(self) // No network write until the recovery receipt is durable.
      let created = try await command("createSession", [
        "workspaceId": workspaceId, "sessionId": sessionId, "machineId": agent.machineId,
        "agentConfigId": agent.id, "userId": userId, "title": String(text.prefix(80)),
      ])
      guard created["state"] as? String == "created",
        (created["session"] as? [String: Any])?["id"] as? String == sessionId else {
        phase = created["state"] as? String == "rejected" ? .failed : .unknown
        try persist(self)
        return phase
      }
      phase = .created
      try persist(self)
      let watching = try await command("ensureSession", ["workspaceId": workspaceId, "sessionId": sessionId])
      guard watching["state"] as? String == "watching" else {
        throw NSError(domain: "LodyShareProbe", code: 2)
      }
      phase = .sending
      try persist(self)
      let sent = try await command("sendTurn", [
        "id": sendId, "sessionId": sessionId, "machineId": agent.machineId,
        "userId": userId, "text": text, "cliType": agent.cliType, "agentType": agent.agentType,
      ])
      switch sent["state"] as? String {
      case "accepted": phase = .accepted
      case "uploaded": phase = .uploaded
      case "not_sent": phase = .failed
      default: phase = .unknown
      }
      try persist(self)
      return phase
    } catch {
      phase = .unknown
      try? persist(self)
      throw error
    }
  }
}
