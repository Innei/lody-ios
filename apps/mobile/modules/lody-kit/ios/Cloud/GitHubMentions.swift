import Foundation

/// Official Cloud token broker + GitHub's bounded open issue/PR listing.
/// Neither the login credential nor the repository token leaves native memory.
@MainActor enum GitHubMentions {
  static func load(workspace: String, repo: String) async throws -> [String: Any] {
    guard repo.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
          ![".", ".."].contains(repo.components(separatedBy: "/").last ?? ""),
          let token = try AuthKeychain.read(), !token.isEmpty else { throw failure() }
    let auth = try await request("https://backend.lody.ai/api/auth/convex/token", token: token) as? [String: Any]
    guard let jwt = auth?["token"] as? String, !jwt.isEmpty else { throw failure() }
    let broker = try await request(
      "https://convex.lody.ai/api/action",
      token: jwt,
      body: ["path": "github:getAccessTokenByRepoNameForClient", "format": "convex_encoded_json", "args": [["workspaceId": workspace, "repoFullName": repo]]]
    ) as? [String: Any]
    guard broker?["status"] as? String == "success", let result = broker?["value"] as? [String: Any] else { throw failure() }
    if result["success"] as? Bool != true {
      if ["repo_not_linked", "installation_not_found", "repo_not_authorized"].contains(result["errorCode"] as? String ?? "") {
        return ["items": [], "truncated": false, "incomplete": false]
      }
      throw failure()
    }
    guard let repositoryToken = result["token"] as? String, !repositoryToken.isEmpty else { throw failure() }
    var items: [[String: Any]] = []
    var seen = Set<Int>()
    var count = 0
    for page in 1...2 {
      try Task.checkCancellation()
      guard let rows = try await request(
        "https://api.github.com/repos/\(repo)/issues?state=open&per_page=100&sort=updated&direction=desc&page=\(page)",
        token: repositoryToken
      ) as? [[String: Any]] else { throw failure() }
      count += rows.count
      for row in rows {
        guard row["state"] as? String == "open", let number = row["number"] as? Int, number > 0,
              let title = row["title"] as? String, !title.isEmpty, title.count <= 4096,
              seen.insert(number).inserted else { continue }
        let kind = row["pull_request"] == nil ? "issue" : "pr"
        items.append(["path": "\(kind):\(number)", "name": title, "kind": kind, "subtitle": "\(repo) #\(number)", "insertText": "#\(number)"])
      }
      if rows.count < 100 { break }
    }
    return ["items": items, "truncated": count >= 200, "incomplete": false]
  }

  private static func failure() -> NSError {
    NSError(domain: "LodyKit.GitHubMentions", code: 1, userInfo: [NSLocalizedDescriptionKey: "github_mentions_unavailable"])
  }
  private static func request(_ address: String, token: String? = nil, body: [String: Any]? = nil) async throws -> Any {
    var request = URLRequest(url: URL(string: address)!, timeoutInterval: 15)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 8 * 1024 * 1024 else { throw failure() }
    return try JSONSerialization.jsonObject(with: data)
  }
}
