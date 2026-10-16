import Foundation

/// A small allowlist of official settings operations. Credentials stay native.
@MainActor enum WorkspaceSettingsCloud {
  typealias Call = (String, String, [String: Any]) async throws -> Any

  static func run(_ payload: String) async throws -> String {
    guard let token = try AuthKeychain.read(), !token.isEmpty,
          let data = payload.data(using: .utf8), data.count <= 16 * 1024,
          let args = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let workspace = args["workspaceId"] as? String, !workspace.isEmpty, workspace.count <= 200 else { throw GitHubCloud.failure() }
    let session = try await GitHubCloud.request("https://backend.lody.ai/api/auth/get-session", token: token) as? [String: Any]
    guard try AuthKeychain.read() == token,
          let user = (session?["user"] as? [String: Any])?["id"] as? String, !user.isEmpty else { throw GitHubCloud.failure() }
    let value = try await execute(args, workspace: workspace, user: user) { kind, path, fields in
      guard try AuthKeychain.read() == token else { throw GitHubCloud.failure() }
      return try await GitHubCloud.call(kind, path: path, args: fields)
    }
    guard try AuthKeychain.read() == token else { throw GitHubCloud.failure() }
    return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
  }

  static func projectRows(_ value: Any) throws -> [[String: Any]] {
    guard let rows = value as? [[String: Any]], rows.count <= 10000 else { throw GitHubCloud.failure() }
    var keys = Set<String>()
    var projected: [[String: Any]] = []
    for row in rows {
      guard let machine = row["machineId"] as? String, !machine.isEmpty,
            let project = row["localProjectId"] as? String, !project.isEmpty,
            let owner = row["ownerUserId"] as? String, !owner.isEmpty,
            let shared = row["sharedWithTeam"] as? Bool, let date = row["updatedAt"] as? Double, date.isFinite, date >= 0,
            keys.insert("\(machine.utf8.count):\(machine)\(project)").inserted else { throw GitHubCloud.failure() }
      projected.append(["machineId": machine, "localProjectId": project, "ownerUserId": owner, "sharedWithTeam": shared, "updatedAt": date])
    }
    return projected
  }

  static func execute(_ request: [String: Any], workspace: String, user: String, call: Call) async throws -> [String: Any] {
    guard request["page"] as? String == "projects" else { throw GitHubCloud.failure() }
    let scope: [String: Any] = ["workspaceId": workspace]
    let rows = try projectRows(await call("query", "localProjects:listVisibleLocalProjects", scope))
    if request["action"] as? String == "set" {
      guard let machine = request["machineId"] as? String,
            let project = request["localProjectId"] as? String,
            let shared = request["sharedWithTeam"] as? Bool,
            rows.contains(where: { $0["machineId"] as? String == machine && $0["localProjectId"] as? String == project && $0["ownerUserId"] as? String == user }) else { throw GitHubCloud.failure() }
      let result = try await call("mutation", "localProjects:setLocalProjectSharedWithTeam", ["workspaceId": workspace, "machineId": machine, "localProjectId": project, "sharedWithTeam": shared]) as? [String: Any]
      guard result?["success"] as? Bool == true, result?["sharedWithTeam"] as? Bool == shared else { throw GitHubCloud.failure() }
      let fresh = try projectRows(await call("query", "localProjects:listVisibleLocalProjects", scope))
      guard fresh.contains(where: { $0["machineId"] as? String == machine && $0["localProjectId"] as? String == project && $0["sharedWithTeam"] as? Bool == shared }) else { throw GitHubCloud.failure() }
      return ["rows": fresh, "userId": user]
    }
    guard request["action"] as? String == "list" else { throw GitHubCloud.failure() }
    return ["rows": rows, "userId": user]
  }
}
