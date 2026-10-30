import Foundation

public struct WorkspaceMembers: Decodable, Equatable, Sendable {
  public struct Member: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var email: String
    public var image: String?
    public var role: String

    public init(id: String, name: String, email: String, image: String? = nil, role: String) {
      self.id = id
      self.name = name
      self.email = email
      self.image = image
      self.role = role
    }
  }

  public var members: [Member]
  public var role: String?

  public init(members: [Member], role: String?) {
    self.members = members
    self.role = role
  }

  public var canEdit: Bool {
    let roles = Set((role ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    return !roles.isDisjoint(with: ["admin", "owner"])
  }

  // Only display fields leave native code; the organization payload is never forwarded whole.
  @MainActor
  public static func project(_ organization: Any, workspace: String, user: String) throws -> [String: Any] {
    guard let organization = organization as? [String: Any], organization["id"] as? String == workspace,
          let rows = organization["members"] as? [[String: Any]], rows.count <= 10000 else { throw GitHubCloud.failure() }
    var role: Any = NSNull()
    let members = try rows.map { row -> [String: Any] in
      guard let id = row["userId"] as? String, !id.isEmpty, let roles = row["role"] as? String,
            let profile = row["user"] as? [String: Any], let email = profile["email"] as? String else { throw GitHubCloud.failure() }
      if id == user { role = roles }
      var member: [String: Any] = ["id": id, "name": profile["name"] as? String ?? "", "email": email, "role": roles]
      if let image = profile["image"] as? String, !image.isEmpty { member["image"] = image }
      return member
    }
    return ["members": members, "role": role]
  }

  @MainActor
  public static func load(workspaceId: String) async throws -> WorkspaceMembers {
    let request = String(decoding: try JSONSerialization.data(withJSONObject: ["workspaceId": workspaceId, "page": "members"]), as: UTF8.self)
    return try JSONDecoder().decode(WorkspaceMembers.self, from: Data(try await WorkspaceSettingsCloud.run(request).utf8))
  }
}
