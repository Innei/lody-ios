import Foundation

/// Public Lody Cloud team contracts. Credentials and JWTs never leave native code.
@MainActor enum TeamManagement {
  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  }
  private static let transport = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
  private static let entryOperations: Set<String> = ["userInvitations", "invitePreview", "acceptInvitation", "rejectInvitation", "joinPreview", "submitRequest"]
  private static let errorCodes: Set<String> = [
    "free_workspace_member_limit_reached", "workspace_transfer_not_owner", "workspace_transfer_invalid_member",
    "workspace_transfer_deleting", "workspace_transfer_billing_owner_mismatch", "workspace_transfer_contact_support",
    "workspace_transfer_billing_busy", "workspace_transfer_free_limit", "EMAIL_VERIFICATION_REQUIRED_FOR_INVITATION",
    "YOU_ARE_NOT_THE_RECIPIENT_OF_THE_INVITATION", "INVITATION_NOT_FOUND", "INVITATION_ALREADY_ACCEPTED",
    "YOU_ARE_NOT_ALLOWED_TO_UPDATE_THIS_MEMBER", "YOU_ARE_NOT_ALLOWED_TO_DELETE_THIS_MEMBER",
  ]
  private static func failure(_ code: String = "team_unavailable") -> NSError {
    NSError(domain: "LodyKit.Team", code: 1, userInfo: [NSLocalizedDescriptionKey: code])
  }
  private static func identifier(_ value: Any?) throws -> String {
    guard let value = value as? String,
      value.range(of: #"^[a-zA-Z0-9_-]{1,256}$"#, options: .regularExpression) != nil else { throw failure("team_invalid_request") }
    return value
  }
  private static func projectedMember(_ value: Any) throws -> [String: Any] {
    guard let member = value as? [String: Any], let user = member["user"] as? [String: Any],
      let email = user["email"] as? String, !email.isEmpty,
      let role = member["role"] as? String, !role.isEmpty else { throw failure("team_invalid_response") }
    var result: [String: Any] = ["id": try identifier(member["id"]), "userId": try identifier(member["userId"]),
      "name": user["name"] as? String ?? email, "email": email, "role": role]
    if let image = user["image"] as? String, let url = URL(string: image),
      url.scheme == "https", url.user == nil, url.password == nil { result["image"] = image }
    return result
  }
  private static func projectedInvitation(_ value: Any) throws -> [String: Any] {
    guard let row = value as? [String: Any], let email = row["email"] as? String,
      let role = row["role"] as? String, let status = row["status"] as? String,
      let expires = row["expiresAt"], expires is String || expires is NSNumber else { throw failure("team_invalid_response") }
    var result: [String: Any] = ["id": try identifier(row["id"]), "organizationId": try identifier(row["organizationId"]),
      "email": email, "role": role, "status": status, "expiresAt": expires]
    if let name = row["organizationName"] as? String { result["organizationName"] = name }
    return result
  }
  static func run(_ payload: String, session: URLSession? = nil,
    scopeCheck: @MainActor () throws -> Void = {}) async throws -> String {
    guard payload.utf8.count <= 64 * 1024,
      let envelope = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
      Set(envelope.keys).isSubset(of: ["userId", "workspaceId", "operation", "args"]),
      let workspace = envelope["workspaceId"] as? String, let operation = envelope["operation"] as? String,
      let args = envelope["args"] as? [String: Any] else { throw failure("team_invalid_request") }
    let userID = try identifier(envelope["userId"])
    if workspace.isEmpty {
      guard entryOperations.contains(operation) else { throw failure("team_invalid_request") }
    } else {
      _ = try identifier(workspace)
      guard !entryOperations.contains(operation) else { throw failure("team_invalid_request") }
    }
    let allowedArguments: [String: Set<String>] = [
      "state": [], "members": ["offset"], "invitations": [], "userInvitations": [],
      "invite": ["email", "role"], "cancelInvitation": ["invitationId"], "invitePreview": ["invitationId"],
      "acceptInvitation": ["invitationId"], "rejectInvitation": ["invitationId"],
      "updateRole": ["memberId", "role"], "removeMember": ["memberId"], "leave": [], "transfer": ["memberId"],
      "ownerState": [], "rotateLink": ["expiresInDays"], "revokeLink": ["linkId"],
      "reviewRequest": ["requestId", "decision"], "joinPreview": ["token"], "submitRequest": ["token", "reason"],
    ]
    guard let allowed = allowedArguments[operation], Set(args.keys) == allowed,
      let credential = try AuthKeychain.read(), !credential.isEmpty else { throw failure("team_invalid_request") }
    func check() throws {
      try Task.checkCancellation()
      guard try AuthKeychain.read() == credential else { throw failure("team_scope_changed") }
      try scopeCheck()
    }
    let transport = session ?? Self.transport
    func request(_ address: String, token: String, body: [String: Any]? = nil, query: [String: String] = [:]) async throws -> Any {
      try check()
      var url = URLComponents(string: address)!
      if !query.isEmpty { url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
      var request = URLRequest(url: url.url!, timeoutInterval: 30)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      if let body {
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      }
      let (file, response) = try await transport.download(for: request)
      defer { try? FileManager.default.removeItem(at: file) }
      try check()
      guard let response = response as? HTTPURLResponse,
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024 else { throw failure() }
      let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.fragmentsAllowed])
      if !(200..<300).contains(response.statusCode) {
        let code = (value as? [String: Any])?["code"] as? String ?? ""
        if errorCodes.contains(code) { throw failure(code) }
        if response.statusCode == 401 { throw failure("team_signed_out") }
        if response.statusCode == 403 { throw failure("team_permission_denied") }
        throw failure()
      }
      return value
    }
    func auth(_ path: String, body: [String: Any]? = nil, query: [String: String] = [:]) async throws -> Any {
      try await request("https://backend.lody.ai/api/auth\(path)", token: credential, body: body, query: query)
    }
    guard let current = try await auth("/get-session") as? [String: Any],
      let currentUser = current["user"] as? [String: Any], currentUser["id"] as? String == userID else { throw failure("team_scope_changed") }
    var jwt: String?
    func convex(_ path: String, _ values: [String: Any], mutation: Bool = false) async throws -> Any {
      if jwt == nil {
        guard let token = try await auth("/convex/token") as? [String: Any], let value = token["token"] as? String, !value.isEmpty else { throw failure() }
        jwt = value
      }
      guard let result = try await request("https://convex.lody.ai/api/\(mutation ? "mutation" : "query")", token: jwt!,
        body: ["path": path, "format": "convex_encoded_json", "args": [values]]) as? [String: Any] else { throw failure() }
      guard result["status"] as? String == "success", let value = result["value"] else {
        let code = (result["errorData"] as? [String: Any])?["code"] as? String ?? ""
        throw failure(errorCodes.contains(code) ? code : "team_permission_denied")
      }
      return value
    }
    func member(_ field: String, _ value: String) async throws -> [String: Any] {
      guard let result = try await auth("/organization/list-members", query: ["organizationId": workspace,
        "filterField": field, "filterOperator": "eq", "filterValue": value, "limit": "1", "offset": "0"]) as? [String: Any],
        let members = result["members"] as? [[String: Any]], members.count == 1,
        let row = members.first, row["organizationId"] as? String == workspace else { throw failure("team_permission_denied") }
      return row
    }
    var viewer: [String: Any]?
    var roles: [String] = []
    if !workspace.isEmpty {
      viewer = try await member("userId", userID)
      roles = (viewer?["role"] as? String ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    func requireManage() throws {
      guard roles.contains("owner") || roles.contains("admin") else { throw failure("team_permission_denied") }
    }
    func requireOwner() throws { guard roles.contains("owner") else { throw failure("team_permission_denied") } }
    func target() async throws -> [String: Any] {
      let row = try await member("id", identifier(args["memberId"]))
      guard row["userId"] as? String != userID,
        ["member", "admin"].contains(row["role"] as? String ?? "") else { throw failure("team_permission_denied") }
      return row
    }
    var result: Any = NSNull()
    switch operation {
    case "state":
      guard let organization = try await auth("/organization/get-full-organization", query: ["organizationId": workspace, "membersLimit": "1"]) as? [String: Any],
        organization["id"] as? String == workspace, let name = organization["name"] as? String, !name.isEmpty else { throw failure("team_invalid_response") }
      result = ["workspaceName": name, "viewer": try projectedMember(viewer!),
        "limit": (try? await convex("billing:getWorkspaceMemberLimitState", ["workspaceId": workspace])) ?? NSNull(),
        "seat": (try? await convex("billing:getWorkspaceSeatInvitePreview", ["workspaceId": workspace])) ?? NSNull()]
    case "members":
      guard let offset = args["offset"] as? Int, offset >= 0 else { throw failure("team_invalid_request") }
      guard let page = try await auth("/organization/list-members", query: ["organizationId": workspace,
        "offset": String(offset), "limit": "50", "sortBy": "createdAt", "sortDirection": "asc"]) as? [String: Any],
        let members = page["members"] as? [[String: Any]], members.count <= 50,
        members.allSatisfy({ $0["organizationId"] as? String == workspace }), let total = page["total"] as? Int else { throw failure("team_invalid_response") }
      result = ["members": try members.map(projectedMember), "total": total]
    case "invitations", "userInvitations":
      if operation == "invitations" { try requireManage() }
      let values = try await auth(operation == "invitations" ? "/organization/list-invitations" : "/organization/list-user-invitations",
        query: operation == "invitations" ? ["organizationId": workspace] : [:])
      guard let rows = values as? [[String: Any]], workspace.isEmpty || rows.allSatisfy({ $0["organizationId"] as? String == workspace }) else { throw failure("team_invalid_response") }
      result = try rows.map(projectedInvitation)
    case "invite":
      try requireManage()
      guard let email = args["email"] as? String, email.utf8.count <= 254,
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil,
        let role = args["role"] as? String, ["member", "admin"].contains(role) else { throw failure("team_invalid_request") }
      _ = try await auth("/organization/invite-member", body: ["organizationId": workspace, "email": email, "role": role])
    case "cancelInvitation":
      try requireManage()
      let id = try identifier(args["invitationId"])
      guard let rows = try await auth("/organization/list-invitations", query: ["organizationId": workspace]) as? [[String: Any]],
        rows.contains(where: { $0["id"] as? String == id && $0["organizationId"] as? String == workspace && $0["status"] as? String == "pending" }) else { throw failure("team_permission_denied") }
      _ = try await auth("/organization/cancel-invitation", body: ["invitationId": id])
    case "updateRole", "removeMember", "transfer":
      if operation == "transfer" { try requireOwner() } else { try requireManage() }
      let row = try await target(), id = try identifier(row["id"])
      if operation == "transfer" {
        _ = try await convex("auth:transferWorkspaceOwnership", ["workspaceId": workspace, "targetMemberId": id], mutation: true)
      } else if operation == "removeMember" {
        _ = try await auth("/organization/remove-member", body: ["organizationId": workspace, "memberIdOrEmail": id])
      } else {
        guard let role = args["role"] as? String, ["member", "admin"].contains(role) else { throw failure("team_invalid_request") }
        _ = try await auth("/organization/update-member-role", body: ["organizationId": workspace, "memberId": id, "role": role])
      }
    case "leave":
      guard !roles.contains("owner") else { throw failure("team_owner_must_transfer") }
      _ = try await auth("/organization/leave", body: ["organizationId": workspace])
    case "ownerState", "rotateLink", "revokeLink", "reviewRequest":
      try requireOwner()
      if operation == "ownerState" {
        result = try await convex("workspaceJoinRequests:getOwnerState", ["workspaceId": workspace])
      } else if operation == "rotateLink" {
        guard let days = args["expiresInDays"] as? Int, [7, 30, 90].contains(days) else { throw failure("team_invalid_request") }
        _ = try await convex("workspaceJoinRequests:rotateLink", ["workspaceId": workspace, "expiresInDays": days], mutation: true)
      } else {
        guard let state = try await convex("workspaceJoinRequests:getOwnerState", ["workspaceId": workspace]) as? [String: Any] else { throw failure() }
        if operation == "revokeLink" {
          let id = try identifier(args["linkId"])
          guard (state["activeLink"] as? [String: Any])?["id"] as? String == id else { throw failure("team_permission_denied") }
          _ = try await convex("workspaceJoinRequests:revokeLink", ["workspaceId": workspace, "linkId": id], mutation: true)
        } else {
          let id = try identifier(args["requestId"])
          guard let decision = args["decision"] as? String, ["approved", "rejected"].contains(decision),
            let pending = state["pendingRequests"] as? [[String: Any]], pending.contains(where: { $0["id"] as? String == id }) else { throw failure("team_permission_denied") }
          _ = try await convex("workspaceJoinRequests:reviewRequest", ["requestId": id, "decision": decision], mutation: true)
        }
      }
    case "invitePreview":
      result = try await convex("auth:getInvitationPreview", ["invitationId": try identifier(args["invitationId"])])
    case "acceptInvitation", "rejectInvitation":
      let id = try identifier(args["invitationId"])
      guard let invitation = try await auth("/organization/get-invitation", query: ["id": id]) as? [String: Any],
        let recipient = invitation["email"] as? String, let email = currentUser["email"] as? String,
        recipient.lowercased() == email.lowercased() else { throw failure("YOU_ARE_NOT_THE_RECIPIENT_OF_THE_INVITATION") }
      _ = try await auth(operation == "acceptInvitation" ? "/organization/accept-invitation" : "/organization/reject-invitation", body: ["invitationId": id])
    case "joinPreview", "submitRequest":
      let token = try identifier(args["token"])
      if operation == "joinPreview" {
        result = try await convex("workspaceJoinRequests:getLinkPreview", ["token": token])
      } else {
        guard let reason = args["reason"] as? String, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          reason.utf8.count <= 4096 else { throw failure("team_invalid_request") }
        _ = try await convex("workspaceJoinRequests:submitRequest", ["token": token, "reason": reason], mutation: true)
      }
    default: throw failure("team_invalid_request")
    }
    try check()
    return String(data: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]), encoding: .utf8)!
  }
}
