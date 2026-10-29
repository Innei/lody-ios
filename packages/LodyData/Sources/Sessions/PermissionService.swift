import Foundation
import LodyCore

@MainActor
public struct PermissionService: Sendable {
  public var detail: @MainActor (String, SessionPermission) async throws -> RuntimeContract.ItemDetail
  public var respond: @MainActor (RuntimeContract.RespondPermissionParams) async throws -> RuntimeContract.RespondPermissionResultState

  public static let live = Self(
    detail: { sessionId, target in
      guard let runtime = DataRuntime.current, runtime.sessionId == sessionId else { throw OutboxError.scopeExpired }
      return try await runtime.perform(RuntimeContract.Calls.ItemDetail.self, .init(
        sessionId: sessionId, entryId: target.entryId, itemId: target.itemId
      ))
    },
    respond: { params in
      guard let runtime = DataRuntime.current, runtime.sessionId == params.sessionId else { throw OutboxError.scopeExpired }
      return try await runtime.perform(RuntimeContract.Calls.RespondPermission.self, params).state
    }
  )

  public init(detail: @escaping @MainActor (String, SessionPermission) async throws -> RuntimeContract.ItemDetail, respond: @escaping @MainActor (RuntimeContract.RespondPermissionParams) async throws -> RuntimeContract.RespondPermissionResultState) {
    self.detail = detail
    self.respond = respond
  }
}
