import AppKit
import ChatKitCore
import LodyCore
import LodyData

@MainActor
struct MacTranscriptSource {
  var start: @MainActor (_ changed: @escaping @MainActor (SessionFeedState) -> Void) -> Void
  var stop: @MainActor () -> Void
  var detail: MacPermissionFlow.Detail
  var respond: MacPermissionFlow.Respond
  var media: CKMediaProvider?
  var respondQuestions: MacPermissionFlow.RespondQuestions = { _, _, _ in throw OutboxError.scopeExpired }
  var queueService: MacQueueService?
  var userId = ""
  var reconnect: () -> Void = {}
  var previewFile: (@MainActor (CKMediaRef) async throws -> MacInspectionContent)?

  static func live(sessionId: String, state: SessionListState, permission: PermissionService = .live) -> MacTranscriptSource {
    let feed = SessionFeed(sessionId: sessionId, userId: state.userId, workspaceId: state.workspaceId)
    return MacTranscriptSource(
      start: { [feed] changed in
        feed.changed = { [weak feed] in if let feed { changed(feed.state) } }
        feed.start()
      },
      stop: { feed.finish() },
      detail: { target in
        try await permission.detail(sessionId, target).options?.map { .init(optionId: $0.optionId, name: $0.name, kind: $0.kind) }
      },
      respond: { target, optionId in
        try await permission.respond(.init(
          sessionId: sessionId, entryId: target.entryId, itemId: target.itemId,
          requestId: target.requestId, optionId: optionId
        ))
      },
      media: MacMediaProvider(workspace: state.workspaceId, session: sessionId),
      respondQuestions: { target, optionId, answers in
        try await permission.respond(.init(sessionId: sessionId, entryId: target.entryId, itemId: target.itemId,
                                          requestId: target.requestId, optionId: optionId, answers: answers))
      },
      queueService: .live(sessionId: sessionId, workspace: state.workspaceId, user: state.userId),
      userId: state.userId,
      reconnect: { feed.reconnect() },
      previewFile: { ref in
        guard let owner = DataRuntime.current, owner.userId == state.userId, owner.workspace == state.workspaceId, owner.sessionId == sessionId else { throw OutboxError.scopeExpired }
        let content = try await MacMediaProvider(workspace: state.workspaceId, session: sessionId).previewFile(for: ref)
        guard DataRuntime.current === owner, owner.userId == state.userId, owner.workspace == state.workspaceId, owner.sessionId == sessionId else { throw OutboxError.scopeExpired }
        try Task.checkCancellation()
        return content
      }
    )
  }
}
