import Foundation
import os

enum AuthKeychain {
  static let value = OSAllocatedUnfairLock(initialState: "synthetic-account-credential")
  static func read() throws -> String? { value.withLock { $0 } }
}
final class TeamProtocol: URLProtocol {
  struct State {
    var role = "owner"
    var crossWorkspaceTarget = false
    var wrongRecipient = false
    var rejectInvite = false
    var swapCredential = false
    var calls: [String] = []
  }
  static let state = OSAllocatedUnfairLock(initialState: State())
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!, path = url.path
    let call = "\(request.httpMethod ?? "GET") \(url.host!)\(path)"
    let snapshot = Self.state.withLock { state in state.calls.append(call); return state }
    var response: Any
    var status = 200
    func member(_ id: String, user: String, role: String, workspace: String = "workspace") -> [String: Any] {
      ["id": id, "userId": user, "organizationId": workspace, "role": role,
        "user": ["name": user, "email": "\(user)@example.invalid", "privateCredential": "never-return-this"]]
    }
    if url.host == "backend.lody.ai" {
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-account-credential")
      switch path {
      case "/api/auth/get-session":
        response = ["user": ["id": "user", "email": "user@example.invalid"], "session": ["token": "never-return-this"]]
        if snapshot.swapCredential { AuthKeychain.value.withLock { $0 = "another-account" } }
      case "/api/auth/convex/token": response = ["token": "synthetic-convex-jwt"]
      case "/api/auth/organization/get-full-organization": response = ["id": "workspace", "name": "Current workspace name", "privateCredential": "never-return-this"]
      case "/api/auth/organization/list-members":
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        precondition(query["organizationId"] == "workspace")
        if query["filterField"] == "userId" { response = ["members": [member("self", user: "user", role: snapshot.role)], "total": 1] }
        else if query["filterField"] == "id" { response = ["members": [member("candidate", user: "candidate-user", role: "member", workspace: snapshot.crossWorkspaceTarget ? "another-workspace" : "workspace")], "total": 1] }
        else { precondition(query["limit"] == "50"); response = ["members": [member("self", user: "user", role: snapshot.role)], "total": 1] }
      case "/api/auth/organization/invite-member":
        if snapshot.rejectInvite { status = 403; response = ["code": "NOT_ALLOWED", "message": "private server token never-return-this"] }
        else { response = ["id": "invited"] }
      case "/api/auth/organization/update-member-role", "/api/auth/organization/remove-member", "/api/auth/organization/leave": response = NSNull()
      case "/api/auth/organization/get-invitation": response = ["email": snapshot.wrongRecipient ? "another@example.invalid" : "user@example.invalid"]
      case "/api/auth/organization/accept-invitation", "/api/auth/organization/reject-invitation": response = NSNull()
      default: fatalError("Unexpected auth endpoint \(path)")
      }
    } else {
      precondition(url.host == "convex.lody.ai" && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-convex-jwt")
      var data = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
      }
      let payload = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
      let operation = payload["path"] as! String
      if operation == "auth:transferWorkspaceOwnership" {
        precondition(path == "/api/mutation")
        let args = (payload["args"] as! [[String: Any]])[0]
        precondition(args["workspaceId"] as? String == "workspace" && args["targetMemberId"] as? String == "candidate")
      } else { precondition(["billing:getWorkspaceMemberLimitState", "billing:getWorkspaceSeatInvitePreview"].contains(operation) && path == "/api/query") }
      response = ["status": "success", "value": NSNull()]
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed]))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main @MainActor struct Check {
  static func main() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TeamProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    func run(_ operation: String, _ args: [String: Any] = [:], workspace: String = "workspace", user: String = "user") async throws -> String {
      let payload = String(data: try JSONSerialization.data(withJSONObject: ["operation": operation, "args": args, "workspaceId": workspace, "userId": user]), encoding: .utf8)!
      return try await TeamManagement.run(payload, session: session)
    }
    func rejected(_ action: () async throws -> String) async {
      do { _ = try await action(); fatalError("Unsafe team action accepted") } catch {}
    }
    let projected = try await run("members", ["offset": 0])
    precondition(projected.contains("user@example.invalid") && !projected.contains("never-return-this"))
    let current = try await run("state")
    precondition(current.contains("Current workspace name") && !current.contains("never-return-this"))
    let initial = TeamProtocol.state.withLock { $0.calls.count }
    await rejected { try await run("unknown") }
    await rejected { try await run("invite", ["email": "member@example.invalid", "role": "member"], workspace: "") }
    await rejected { try await run("members", ["offset": 0, "token": "private"]) }
    precondition(TeamProtocol.state.withLock { $0.calls.count } == initial, "Rejected payload must never reach a server")
    await rejected { try await run("members", ["offset": 0], user: "another-user") }
    TeamProtocol.state.withLock { $0.role = "member" }
    await rejected { try await run("invite", ["email": "member@example.invalid", "role": "member"]) }
    precondition(!TeamProtocol.state.withLock { $0.calls }.contains(where: { $0.contains("invite-member") }), "Member must not send invitations")
    TeamProtocol.state.withLock { $0.role = "owner"; $0.crossWorkspaceTarget = true }
    await rejected { try await run("removeMember", ["memberId": "candidate"]) }
    precondition(!TeamProtocol.state.withLock { $0.calls }.contains(where: { $0.contains("remove-member") }), "Cross-workspace member must never be removed")
    TeamProtocol.state.withLock { $0.crossWorkspaceTarget = false }
    _ = try await run("transfer", ["memberId": "candidate"])
    TeamProtocol.state.withLock { $0.rejectInvite = true }
    do { _ = try await run("invite", ["email": "member@example.invalid", "role": "member"]); fatalError("Rejected invitation succeeded") }
    catch { precondition(error.localizedDescription == "team_permission_denied" && !error.localizedDescription.contains("never-return-this")) }
    precondition(TeamProtocol.state.withLock { $0.calls.filter { $0.contains("invite-member") }.count } == 1, "Uncertain invitation must not replay")
    TeamProtocol.state.withLock { $0.wrongRecipient = true }
    await rejected { try await run("acceptInvitation", ["invitationId": "invitation"], workspace: "") }
    precondition(!TeamProtocol.state.withLock { $0.calls }.contains(where: { $0.contains("accept-invitation") }))
    TeamProtocol.state.withLock { $0.swapCredential = true }
    let beforeSwap = TeamProtocol.state.withLock { $0.calls.count }
    await rejected { try await run("members", ["offset": 0]) }
    precondition(TeamProtocol.state.withLock { $0.calls.count } == beforeSwap + 1, "Account changes must fence after get-session")
    print("Team native boundary passed: safe projection, operation whitelist, account/workspace/role fencing, member identifiers, recipient checks and no replay")
  }
}
