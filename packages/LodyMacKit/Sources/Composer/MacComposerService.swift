import Foundation
import LodyCore
import LodyData

@MainActor
struct MacComposerService {
  var options: @MainActor (_ workspaceId: String, _ projectId: String?) async throws -> CreationOptions
  var create: @MainActor (_ draft: CreateSessionDraft, _ payload: [String: Any]) -> Void
  var reply: @MainActor (_ payload: [String: Any], _ choice: ModelChoice) -> Void = { _, _ in }

  static var live: MacComposerService {
    MacComposerService(
      options: { workspaceId, projectId in
        guard let runtime = DataRuntime.current, runtime.workspace == workspaceId else {
          throw DataRuntime.failure("not_ready", String(localized: "native.runtime.sessionNotSynced", bundle: .lodyData))
        }
        let result = try await runtime.workspaceCall(RuntimeContract.Calls.CreationOptions.self) { workspace, _ in
          RuntimeContract.CreationOptionsParams(workspaceId: workspace, projectId: projectId)
        }
        return try JSONDecoder().decode(CreationOptions.self, from: JSONEncoder().encode(result))
      },
      create: { draft, payload in
        let built = CreateDraftRecord(draft: draft, payload: payload)
        _ = OutboxSession.shared.put(user: draft.userId, workspace: draft.workspaceId, json: built.recordJSON)
        NotificationCenter.default.post(name: .lodyMacOpenSession, object: nil, userInfo: ["sessionId": draft.sessionId])
      }
    )
  }
}

extension Notification.Name {
  static let lodyMacOpenSession = Notification.Name("LodyMacOpenSession")
}
