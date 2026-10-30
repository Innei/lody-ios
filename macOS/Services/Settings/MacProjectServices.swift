import Foundation
import LodyData
import Observation

@MainActor
struct MacProjectServices {
  var workspace: @MainActor () -> SettingsWorkspace
  var list: @MainActor (_ workspaceId: String) async throws -> MacVisibility
  var share: @MainActor (_ workspaceId: String, MacProjectRow, Bool) async throws -> MacVisibility

  private struct Request: Encodable {
    var page = "projects"
    var workspaceId: String
    var action: String
    var machineId: String?
    var localProjectId: String?
    var sharedWithTeam: Bool?
  }

  static var live: MacProjectServices {
    MacProjectServices(
      workspace: { SettingsWorkspace.decode(state: CatalogSession.published.json, raw: CatalogSession.published.raw) },
      list: { try await run(Request(workspaceId: $0, action: "list")) },
      share: { workspace, row, shared in
        try await run(Request(workspaceId: workspace, action: "set", machineId: row.machineId, localProjectId: row.localProjectId, sharedWithTeam: shared))
      }
    )
  }

  private static func run(_ request: Request) async throws -> MacVisibility {
    let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
    return try JSONDecoder().decode(MacVisibility.self, from: Data(try await WorkspaceSettingsCloud.run(payload).utf8))
  }
}
