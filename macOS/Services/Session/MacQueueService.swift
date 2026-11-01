import Foundation
import LodyCore
import LodyData

@MainActor
struct MacQueueService {
  var request: @MainActor (RuntimeContract.SessionQueueParams) async throws -> RuntimeContract.SessionQueueResult

  static func live(sessionId: String, workspace: String, user: String) -> Self {
    Self(request: { params in
      guard let runtime = DataRuntime.current, runtime.workspace == workspace, runtime.userId == user,
            runtime.sessionId == sessionId else { throw OutboxError.scopeExpired }
      let result = try await runtime.perform(RuntimeContract.Calls.SessionQueue.self, params)
      guard DataRuntime.current === runtime, runtime.workspace == workspace, runtime.userId == user,
            runtime.sessionId == sessionId else { throw OutboxError.scopeExpired }
      return result
    })
  }
}
