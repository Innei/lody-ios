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
  var attachments = MacDraftAttachments()
  var attachmentNotice = ""
  var run = SessionControl.State()
  var queueCount = 0

  init(mode: Mode) { self.mode = mode }

  var missing: Missing? {
    guard mode == .newSession else { return nil }
    let page = form.current
    if !form.chat && !form.projects.contains(where: { $0.id == page.projectId }) { return .project }
    if page.machine == nil { return .machine }
    if page.agent == nil { return .agent }
    return nil
  }

  var canSend: Bool {
    guard !attachments.items.contains(where: { !FileManager.default.fileExists(atPath: $0.url.path) }) else { return false }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return false }
    switch mode {
    case .newSession: return missing == nil && form.canSend
    case .reply: return replyReady
    }
  }

  var capability: Capability? { mode == .newSession ? form.current.capability : replyCapability }
  var choice: ModelChoice { mode == .newSession ? form.current.choice : replyChoice }
  var projectName: String? {
    guard !form.chat, !form.current.projectId.isEmpty else { return nil }
    return form.projects.first { $0.id == form.current.projectId }?.name
      ?? form.current.options?.project?.name ?? form.current.projectId
  }

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
    ["id": id, "text": text, "startedAt": Int(now.timeIntervalSince1970 * 1000), "attachments": attachments.payload]
  }
}

extension MacComposerModel {
  var modelTitle: String {
    models.first { $0.id == choice.modelId }?.name ?? choice.modelId.flatMap { $0.isEmpty ? nil : $0 }
      ?? String(localized: "mac.composer.defaultModel", bundle: .lodyMac)
  }
  var effortTitle: String {
    guard let effort = choice.effort, !effort.isEmpty else { return String(localized: "mac.composer.defaultEffort", bundle: .lodyMac) }
    if effort.lowercased() == "xhigh" { return String(localized: "mac.composer.extraHigh", bundle: .lodyMac) }
    return effort.replacingOccurrences(of: "_", with: " ").capitalized
  }
  var orderedEfforts: [String] {
    let rank = ["off": 0, "none": 0, "minimal": 1, "low": 2, "medium": 3, "high": 4, "xhigh": 5, "max": 6, "ultra": 7]
    return efforts.enumerated().sorted { lhs, rhs in
      let left = rank[lhs.element.lowercased()], right = rank[rhs.element.lowercased()]
      if let left, let right { return left < right }
      if left != nil { return true }
      if right != nil { return false }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }
}
