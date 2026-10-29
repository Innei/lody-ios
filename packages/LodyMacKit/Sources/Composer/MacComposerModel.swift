import Foundation
import LodyCore
import LodyData

struct MacComposerModel {
  enum Mode: Equatable { case newSession, reply }
  enum Missing: Equatable { case project, machine, agent }

  let mode: Mode
  var text = ""
  var form = CreateSessionForm()
  var replyReady = false
  var replyCapability: Capability?
  var replyChoice = ModelChoice()

  init(mode: Mode) { self.mode = mode }

  var missing: Missing? {
    guard mode == .newSession else { return nil }
    let page = form.current
    if !form.chat && page.projectId.isEmpty { return .project }
    if page.machine == nil { return .machine }
    if page.agent == nil { return .agent }
    return nil
  }

  var canSend: Bool {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    switch mode {
    case .newSession: return missing == nil && form.canSend
    case .reply: return replyReady
    }
  }

  var capability: Capability? { mode == .newSession ? form.current.capability : replyCapability }
  var choice: ModelChoice { mode == .newSession ? form.current.choice : replyChoice }

  var modes: [CapabilityChoice] { capability?.modes ?? [] }
  var models: [CapabilityChoice] { capability?.models ?? [] }
  var efforts: [String] {
    guard let capability else { return [] }
    return capability.reasoningEfforts[choice.modelId ?? ""] ?? capability.reasoningEfforts[""] ?? []
  }

  static func isFullAccess(_ modeId: String) -> Bool {
    let id = modeId.lowercased()
    return id.contains("bypass") || id.contains("full-access") || id.contains("fullaccess") || id == "yolo"
  }

  func payload(id: String, now: Date = Date()) -> [String: Any] {
    ["id": id, "text": text, "startedAt": Int(now.timeIntervalSince1970 * 1000), "attachments": [Any]()]
  }
}
