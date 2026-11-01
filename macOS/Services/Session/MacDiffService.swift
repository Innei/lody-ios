import Foundation
import LodyCore
import LodyData

struct MacDiffRequest: Equatable, Sendable {
  var sessionId: String
  var entryId: String?
  var path: String
}

@MainActor
struct MacDiffService {
  var diff: @MainActor (MacDiffRequest) async throws -> RuntimeContract.DiffResult
  var changes: @MainActor (String) async throws -> RuntimeContract.WorkspaceChanges

  static func live(session: String, workspace: String, user: String) -> Self {
    func runtime() throws -> DataRuntime {
      guard let runtime = DataRuntime.current, runtime.sessionId == session, runtime.workspace == workspace,
            runtime.userId == user else { throw OutboxError.scopeExpired }
      return runtime
    }
    return Self(diff: { request in
      guard request.sessionId == session else { throw OutboxError.scopeExpired }
      let source = try runtime()
      let result: RuntimeContract.DiffResult
      if let entry = request.entryId {
        result = try await source.perform(RuntimeContract.Calls.TurnDiff.self, .init(sessionId: session, entryId: entry, path: request.path))
      } else {
        result = try await source.perform(RuntimeContract.Calls.FileDiff.self, .init(sessionId: session, path: request.path))
      }
      guard try runtime() === source else { throw OutboxError.scopeExpired }
      return result
    }, changes: { id in
      guard id == session else { throw OutboxError.scopeExpired }
      let source = try runtime()
      let result = try await source.perform(RuntimeContract.Calls.WorkspaceChanges.self, .init(sessionId: session))
      guard try runtime() === source else { throw OutboxError.scopeExpired }
      return result
    })
  }
}
