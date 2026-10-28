import Foundation
import LodyCore

@MainActor
struct SessionComposerService {
  var options: @MainActor (_ workspaceId: String, _ projectId: String) async throws -> CreationOptions
  var tier: @MainActor (_ workspaceId: String, _ userId: String) async -> String?

  static let live = SessionComposerService(
    options: { workspaceId, projectId in
      guard let runtime = DataRuntime.current else { throw OutboxError.scopeExpired }
      let payload = SessionController.json(["workspaceId": workspaceId, "projectId": projectId])
      let json: String = try await withCheckedThrowingContinuation { runtime.creationOptions(payload, sink: .continuation($0)) }
      guard let options = CreateJSON.decode(CreationOptions.self, json) else { throw OutboxError.invalidRecord }
      return options
    },
    tier: { workspaceId, userId in
      guard let runtime = DataRuntime.current, runtime.workspace == workspaceId, runtime.userId == userId else { return nil }
      return await runtime.billing.entitlement(workspace: workspaceId, user: userId)?["effectivePlanTier"] as? String
    }
  )
}

@MainActor
final class SessionComposerModel {
  var changed: (() -> Void)?
  private(set) var capability: Capability?
  private(set) var tier: String?
  private let service: SessionComposerService
  private var choice: ModelChoice
  private var hydrated: Bool
  private var restored = ""
  private var snapshotChoice: ModelChoice?
  private var capabilityKey: String?
  private var capabilityTask: Task<Void, Never>?
  private var tierKey = ""
  private var tierTimer: Timer?

  init(choice: ModelChoice?, service: SessionComposerService = .live) {
    self.choice = choice ?? ModelChoice()
    hydrated = choice != nil
    self.service = service
  }

  isolated deinit {
    capabilityTask?.cancel()
    tierTimer?.invalidate()
  }

  var active: ModelChoice { hydrated ? choice : snapshotChoice ?? choice }
  var steerable: Bool { capability?.steer == true }

  func hydrate(pending: OutboxRecord?, ready: Bool, snapshot: ModelChoice?) {
    snapshotChoice = snapshot
    guard ready else { return }
    if let pending {
      guard restored != pending.sendId else { return }
      restored = pending.sendId
      hydrated = true
      choice = pending.send["choice"].flatMap(Self.choice) ?? ModelChoice()
    } else if !hydrated, let snapshot {
      hydrated = true
      choice = snapshot
    }
  }

  func load(workspaceId: String, projectId: String?, session: SessionItem) {
    let key = [workspaceId, projectId ?? "", session.machineId, session.cliType, session.agentType].joined(separator: "\n")
    guard key != capabilityKey else { return }
    capabilityKey = key
    capabilityTask?.cancel()
    guard !workspaceId.isEmpty, let projectId, !session.cliType.isEmpty, !session.agentType.isEmpty else {
      capability = nil
      return
    }
    let service = service
    capabilityTask = Task { [weak self] in
      let options = try? await service.options(workspaceId, projectId)
      guard let self, !Task.isCancelled, self.capabilityKey == key else { return }
      self.capability = options?.capabilities.first {
        $0.machineId == session.machineId && $0.cliType == session.cliType && $0.agentType == session.agentType
      }
      self.changed?()
    }
  }

  func watchTier(workspaceId: String, userId: String, watch: Bool) {
    let key = watch && !workspaceId.isEmpty && !userId.isEmpty ? "\(userId):\(workspaceId)" : ""
    guard key != tierKey else { return }
    tierKey = key
    tier = nil
    tierTimer?.invalidate()
    tierTimer = nil
    guard !key.isEmpty else { return }
    refreshTier(workspaceId, userId, key)
    tierTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshTier(workspaceId, userId, key) }
    }
  }

  private func refreshTier(_ workspaceId: String, _ userId: String, _ key: String) {
    let service = service
    Task { [weak self] in
      let tier = await service.tier(workspaceId, userId)
      guard let self, self.tierKey == key else { return }
      self.tier = ["free", "plus", "enterprise"].contains(tier ?? "") ? tier : nil
      self.changed?()
    }
  }

  var optionsJSON: String {
    let value = active
    let permission = CreateLogic.permissionMode(capability, value)
    var options: [String: Any] = [
      "permissionId": permission?.value ?? "",
      "permissions": (permission?.options ?? []).map { ["id": $0.id, "title": $0.name, "description": $0.description ?? ""] },
      "modelId": value.modelId ?? "",
      "effort": value.effort ?? "",
      "models": (capability?.models ?? []).map { ["id": $0.id, "title": $0.name] },
      "efforts": CreateLogic.effortsFor(capability, modelId: value.modelId).map { ["id": $0, "title": $0] },
    ]
    options["fast"] = CreateLogic.fastMode(capability, value)?.enabled
    return SessionController.json(options)
  }

  func change(_ body: [String: Any]) {
    hydrated = true
    if let permission = body["permissionId"] as? String {
      choice = CreateLogic.withPermissionMode(capability, active, value: permission)
    } else if let fast = body["fast"] as? Bool {
      choice = CreateLogic.withFastMode(capability, active, enabled: fast)
    } else {
      choice.modelId = (body["modelId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      choice.effort = (body["effort"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    changed?()
  }

  var sendChoice: [String: OutboxValue] {
    let value = active
    var result: [String: OutboxValue] = [:]
    let explicit = capability != nil
    for (key, field) in [("modelId", value.modelId), ("effort", value.effort)] {
      if let field { result[key] = .string(field) } else if explicit { result[key] = .null }
    }
    if let mode = value.modeId { result["modeId"] = .string(mode) }
    if let values = value.configOptionValues {
      result["configOptionValues"] = .object(values.mapValues { config in
        switch config {
        case .string(let text): .string(text)
        case .bool(let flag): .bool(flag)
        }
      })
    }
    if let config = capability?.reasoningEffortConfigId { result["reasoningEffortConfigId"] = .string(config) }
    return result
  }

  static func choice(_ value: OutboxValue) -> ModelChoice? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(ModelChoice.self, from: data)
  }
}
