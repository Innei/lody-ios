import LodyCore
import Foundation

@MainActor
public struct CreateSessionService: Sendable {
  public var options: (_ workspaceId: String, _ projectId: String?) async throws -> CreationOptions
  public var repositories: (_ workspaceId: String) async throws -> [String]
  public var branches: (_ workspaceId: String, _ repo: String, _ page: Int) async throws -> CreateBranches
  public var readPrefs: (_ key: String) async -> CreatePrefs?
  public var writePrefs: (_ key: String, _ prefs: CreatePrefs) -> Void
  public var put: (_ userId: String, _ workspaceId: String, _ json: String) -> Task<Void, Error>
  public var persistShare = true

  public static func prefsKey(userId: String, workspaceId: String) -> String { "create:\(userId):\(workspaceId)" }

  public static func githubProject(_ repo: String) -> CreateProject? {
    let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
    guard repo.trimmingCharacters(in: .whitespacesAndNewlines) == repo, parts.count == 2,
          repo.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
          ![".", ".."].contains(String(parts[1])) else { return nil }
    return CreateProject(id: "github:\(repo)", machineId: "", name: repo)
  }

  public init(options: @escaping (_ workspaceId: String, _ projectId: String?) async throws -> CreationOptions, repositories: @escaping (_ workspaceId: String) async throws -> [String], branches: @escaping (_ workspaceId: String, _ repo: String, _ page: Int) async throws -> CreateBranches, readPrefs: @escaping (_ key: String) async -> CreatePrefs?, writePrefs: @escaping (_ key: String, _ prefs: CreatePrefs) -> Void, put: @escaping (_ userId: String, _ workspaceId: String, _ json: String) -> Task<Void, Error>, persistShare: Bool = true) {
    self.options = options
    self.repositories = repositories
    self.branches = branches
    self.readPrefs = readPrefs
    self.writePrefs = writePrefs
    self.put = put
    self.persistShare = persistShare
  }
}
