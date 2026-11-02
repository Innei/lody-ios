import Foundation
import LodyCore
import LodyData
import ChatKitCore

struct MacInspectionFile: Equatable {
  var path: String
  var add: Int? = nil
  var del: Int? = nil
  var kind: String? = nil
}
struct MacInspectionTurn: Equatable {
  var id: String
  var title: String
  var files: [MacInspectionFile]
}
struct MacInspectionDiff: Equatable {
  var handle: String
  var oldKind: String
  var newKind: String
}
struct MacInspectionChanges {
  var base: String
  var files: [MacInspectionFile]
}
struct MacInspectionDirectory {
  struct Entry: Equatable { var name: String; var directory: Bool }
  var entries: [Entry]
  var truncated: Bool
}
enum MacInspectionContent: Equatable { case stored(String), url(URL) }

@MainActor
struct MacInspectionService {
  var diff: (String, String?) async throws -> MacInspectionDiff
  var changes: () async throws -> MacInspectionChanges
  var read: (MacInspectionTarget) async throws -> MacInspectionContent
  var directory: (String) async throws -> MacInspectionDirectory

  static func live(session: String, workspace: String, user: String) -> Self {
    func runtime() throws -> DataRuntime {
      guard let current = DataRuntime.current, current.userId == user, current.workspace == workspace,
            current.sessionId == session else { throw OutboxError.scopeExpired }
      return current
    }
    func validate(_ owner: DataRuntime) throws {
      guard try runtime() === owner else { throw OutboxError.scopeExpired }
      try Task.checkCancellation()
    }
    return Self(diff: { path, entry in
      let owner = try runtime()
      let response: RuntimeContract.DiffResult
      if let entry { response = try await owner.perform(RuntimeContract.Calls.TurnDiff.self, .init(sessionId: session, entryId: entry, path: path)) }
      else { response = try await owner.perform(RuntimeContract.Calls.FileDiff.self, .init(sessionId: session, path: path)) }
      try validate(owner)
      switch response {
      case .unavailable(let result): throw failure(result.message, fallback: "mac.inspection.unavailable")
      case .ok(let result):
        let body = try JSONEncoder().encode(result)
        let handle = ContentStore.shared.put(.init(data: body, kind: "diff", path: path, session: session, mimeType: nil))
        return .init(handle: handle, oldKind: result.old.kind.rawValue, newKind: result.new.kind.rawValue)
      }
    }, changes: {
      let owner = try runtime()
      let response = try await owner.perform(RuntimeContract.Calls.WorkspaceChanges.self, .init(sessionId: session))
      try validate(owner)
      switch response {
      case .unavailable(let result): throw failure(result.message, fallback: "mac.inspection.unavailable")
      case .ok(let result): return .init(base: result.base, files: result.files.map { .init(path: $0.path, add: $0.add, del: $0.del, kind: $0.kind?.rawValue) })
      }
    }, read: { target in
      let owner = try runtime()
      switch target {
      case .file(let path):
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["sessionId": session, "path": path]), as: UTF8.self)
        let response = try await owner.readFile(payload)
        try validate(owner)
        let json = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
        guard json?["status"] as? String == "ok", let handle = json?["handle"] as? String else {
          throw failure(json?["message"] as? String, fallback: "mac.inspection.readFailed")
        }
        return .stored(handle)
      case .attachment(let id, let source, let name):
        let ref = CKMediaRef(id: id, context: ["session": source, "name": name])
        let url = try await MacMediaProvider(workspace: workspace, session: session).fileURL(for: ref)
        try validate(owner)
        return .url(url)
      }
    }, directory: { path in
      let owner = try runtime()
      let result = try await owner.perform(RuntimeContract.Calls.ListDir.self, .init(workspaceId: workspace, sessionId: session, relativePath: path, userId: user))
      try validate(owner)
      return .init(entries: result.entries.map { .init(name: $0.name, directory: $0.type == .directory) }, truncated: result.truncated)
    })
  }

  private static func failure(_ message: String?, fallback: String) -> Error {
    let text = message ?? String(localized: String.LocalizationValue(fallback), bundle: .lodyMac)
    return NSError(domain: "Lody.Inspection", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
  }
}
