import Foundation

/// GitHub credentials never cross the native boundary. No automatic mutation retry.
@MainActor enum GitHubPullRequests {
  static func run(_ payload: String) async throws -> String {
    guard let bytes = payload.data(using: .utf8),
          let args = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          let workspace = args["workspaceId"] as? String, !workspace.isEmpty,
          let repo = args["repository"] as? String,
          repo.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
          ![".", ".."].contains(repo.components(separatedBy: "/").last ?? ""),
          let number = args["number"] as? Int, number > 0,
          let operation = args["operation"] as? String, ["read", "comment"].contains(operation)
    else { throw failure("invalid_request") }
    guard let credential = try AuthKeychain.read(), !credential.isEmpty else { throw failure("unauthorized") }
    let writing = operation == "comment"
    let body = (args["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if writing && (body.isEmpty || body.count > 65536) { throw failure("invalid_comment") }
    let auth = try await request("https://backend.lody.ai/api/auth/convex/token", token: credential)
    guard let jwt = auth["token"] as? String else { throw failure("unauthorized") }
    try checkIdentity(credential)
    let broker = try await request("https://convex.lody.ai/api/action", token: jwt, body: [
      "path": "github:getOperationAccessTokenByRepoNameForClient", "format": "convex_encoded_json",
      "args": [["workspaceId": workspace, "repoFullName": repo, "operation": writing ? "write" : "read"]]
    ])
    try checkIdentity(credential)
    guard broker["status"] as? String == "success", let value = broker["value"] as? [String: Any],
          value["success"] as? Bool == true, let token = value["token"] as? String, !token.isEmpty
    else { throw failure("authorization_required") }
    let base = "https://api.github.com/repos/\(repo)"
    if writing {
      // A transport failure may follow a successful write. Never replay it.
      _ = try await request("\(base)/issues/\(number)/comments", token: token, body: ["body": body], mutation: true)
      try checkIdentity(credential)
      return "{}"
    }
    let pr = try await request("\(base)/pulls/\(number)", token: token)
    try checkIdentity(credential)
    guard let head = pr["head"] as? [String: Any], let sha = head["sha"] as? String,
          sha.range(of: #"^[0-9a-fA-F]{7,64}$"#, options: .regularExpression) != nil,
          let target = pr["base"] as? [String: Any]
    else { throw failure("invalid_response") }
    var state = pr["state"] as? String ?? "closed"
    if pr["merged"] as? Bool == true { state = "merged" }
    else if pr["draft"] as? Bool == true && state == "open" { state = "draft" }
    var result: [String: Any] = [
      "repository": repo, "number": number, "state": state,
      "title": pr["title"] as? String ?? "", "body": pr["body"] as? String ?? "",
      "author": (pr["user"] as? [String: Any])?["login"] as? String ?? "",
      "headRef": head["ref"] as? String ?? "", "baseRef": target["ref"] as? String ?? "", "headSha": sha,
      "additions": pr["additions"] as? Int ?? 0, "deletions": pr["deletions"] as? Int ?? 0,
      "changedFiles": pr["changed_files"] as? Int ?? 0, "commits": pr["commits"] as? Int ?? 0,
      "checks": [], "comments": []
    ]
    do {
      let checks = try await request("\(base)/commits/\(sha)/check-runs?per_page=100", token: token)
      guard let rows = checks["check_runs"] as? [[String: Any]] else { throw failure("invalid_response") }
      result["checks"] = rows.map { row in
        let status = row["status"] as? String ?? "queued"
        let conclusion = row["conclusion"] as? String ?? ""
        let known = ["success", "failure", "neutral", "cancelled", "timed_out", "action_required", "stale", "skipped"].contains(conclusion)
        return [
        "id": row["id"] ?? 0, "name": row["name"] ?? "",
        "status": ["queued", "in_progress", "completed"].contains(status) ? status : "queued", "conclusion": known ? conclusion as Any : NSNull(),
        "htmlUrl": row["html_url"] ?? NSNull(),
        "appName": (row["app"] as? [String: Any])?["name"] ?? NSNull()
      ] }
      result["checksTruncated"] = (checks["total_count"] as? Int ?? 0) > rows.count
    } catch { result["checksError"] = code(error) }
    try checkIdentity(credential)
    do {
      let response = try await request("\(base)/issues/\(number)/comments?per_page=100", token: token)
      guard let rows = response["rows"] as? [[String: Any]] else { throw failure("invalid_response") }
      result["comments"] = rows.map { row in [
        "id": row["id"] ?? 0, "body": row["body"] as? String ?? "",
        "author": (row["user"] as? [String: Any])?["login"] as? String ?? "",
        "url": row["html_url"] as? String ?? ""
      ] }
      result["commentsTruncated"] = response["hasNext"] as? Bool ?? false
    } catch { result["commentsError"] = code(error) }
    try checkIdentity(credential)
    return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
  }

  private static func checkIdentity(_ credential: String) throws {
    guard try AuthKeychain.read() == credential else { throw failure("unauthorized") }
    try Task.checkCancellation()
  }
  private static func failure(_ code: String) -> NSError {
    NSError(domain: "LodyKit.GitHubPullRequests", code: 1, userInfo: [NSLocalizedDescriptionKey: code])
  }
  private static func code(_ error: Error) -> String {
    let value = error as NSError
    return value.domain == "LodyKit.GitHubPullRequests" ? value.localizedDescription : "unavailable"
  }
  private static func request(_ address: String, token: String, body: [String: Any]? = nil, mutation: Bool = false) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: address)!, timeoutInterval: 20)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    if address.hasPrefix("https://api.github.com/") { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let data: Data
    let response: URLResponse
    do { (data, response) = try await URLSession.shared.data(for: request) }
    catch { throw failure(mutation ? "comment_unknown" : "unavailable") }
    guard let response = response as? HTTPURLResponse else { throw failure(mutation ? "comment_unknown" : "unavailable") }
    if response.statusCode == 401 { throw failure("unauthorized") }
    if response.statusCode == 403 { throw failure("forbidden") }
    if response.statusCode == 404 { throw failure("not_found") }
    if response.statusCode == 429 { throw failure("rate_limited") }
    guard (200..<300).contains(response.statusCode) else {
      throw failure(mutation && response.statusCode >= 500 ? "comment_unknown" : "request_failed")
    }
    if mutation { return [:] }
    guard data.count <= 8 * 1024 * 1024 else { throw failure("response_limit") }
    let value = try JSONSerialization.jsonObject(with: data)
    if let rows = value as? [[String: Any]] {
      return ["rows": rows, "hasNext": response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true]
    }
    guard let value = value as? [String: Any] else { throw failure("invalid_response") }
    return value
  }
}
