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
        Task {
          await create(
            draft, payload,
            put: { OutboxSession.shared.put(user: draft.userId, workspace: draft.workspaceId, json: $0) },
            opened: { NotificationCenter.default.post(name: .lodyMacOpenSession, object: nil, userInfo: ["sessionId": $0]) },
            toast: { LodyHosting.current?.toast($0, kind: "error") }
          )
        }
      }
    )
  }

  static func create(
    _ draft: CreateSessionDraft, _ payload: [String: Any],
    put: @MainActor (String) -> Task<Void, Error>,
    opened: @MainActor (String) -> Void,
    toast: @MainActor (String) -> Void
  ) async {
    let built = CreateDraftRecord(draft: draft, payload: payload)
    if (try? await put(built.recordJSON).value) != nil {
      opened(draft.sessionId)
      return
    }
    let reason = String(localized: "send.error.draftSaveShort", bundle: .lodyData)
    toast(reason)
    guard let failed = built.record?.with(phase: "failed", reason: reason), let data = try? JSONEncoder().encode(failed) else { return }
    if (try? await put(String(decoding: data, as: UTF8.self)).value) != nil { opened(draft.sessionId) }
  }
}

extension Notification.Name {
  static let lodyMacOpenSession = Notification.Name("LodyMacOpenSession")
}
