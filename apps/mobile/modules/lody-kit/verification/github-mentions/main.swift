import Foundation
import os

enum AuthKeychain { static func read() throws -> String? { "synthetic-app-token" } }

final class GitHubProtocol: URLProtocol {
  static let urls = OSAllocatedUnfairLock(initialState: [String]())
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let address = request.url!.absoluteString
    Self.urls.withLock { $0.append(address) }
    var body: Any = [:]
    var status = 200
    if request.url?.host == "backend.lody.ai" {
      assert(request.url?.path == "/api/auth/convex/token")
      assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-app-token")
      body = ["token": "synthetic-convex-jwt"]
    } else if request.url?.host == "convex.lody.ai" {
      assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-convex-jwt")
      var data = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          data.append(contentsOf: buffer.prefix(count))
        }
      }
      let payload = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
      assert(payload["path"] as? String == "github:getAccessTokenByRepoNameForClient")
      let args = (payload["args"] as! [[String: Any]])[0]
      assert(args["cliToken"] == nil, "Login credentials are not CLI tokens")
      assert(args["repoFullName"] as? String == "LodyAI/Lody")
      let workspace = args["workspaceId"] as! String
      if workspace == "unlinked" {
        body = ["status": "success", "value": ["success": false, "errorCode": "repo_not_linked"]]
      } else {
        body = ["status": "success", "value": ["success": true, "token": "synthetic-repo-" + workspace]]
      }
    } else {
      assert(request.url?.host == "api.github.com")
      assert(request.url?.path == "/repos/LodyAI/Lody/issues")
      let token = request.value(forHTTPHeaderField: "Authorization")!
      assert(token.hasPrefix("Bearer synthetic-repo-"), "App credentials must never go to GitHub")
      if token.hasSuffix("failure") { status = 503 }
      if token.hasSuffix("full") {
        let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
        let offset = (Int(page)! - 1) * 100
        body = (1...100).map { ["number": offset + $0, "title": "Issue \(offset + $0)", "state": "open"] as [String: Any] }
      } else {
        body = [
          ["number": 11, "title": "Issue", "state": "open"],
          ["number": 12, "title": "PR", "state": "open", "pull_request": [:]],
          ["number": 13, "title": "Closed", "state": "closed"],
          ["number": 11, "title": "Duplicate", "state": "open"],
        ] as [[String: Any]]
      }
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main @MainActor struct Check {
  static func main() async throws {
    URLProtocol.registerClass(GitHubProtocol.self)
    let linked = try await GitHubMentions.load(workspace: "linked", repo: "LodyAI/Lody")
    let items = linked["items"] as! [[String: Any]]
    assert(items.count == 2 && items[0]["kind"] as? String == "issue" && items[1]["kind"] as? String == "pr")
    assert(items[0]["insertText"] as? String == "#11" && items[1]["insertText"] as? String == "#12")
    assert(!String(describing: linked).contains("synthetic"), "Projected catalogs must never expose credentials")
    let before = GitHubProtocol.urls.withLock { $0.count }
    let unlinked = try await GitHubMentions.load(workspace: "unlinked", repo: "LodyAI/Lody")
    assert((unlinked["items"] as! [Any]).isEmpty)
    assert(GitHubProtocol.urls.withLock { $0.count } == before + 2, "Unconnected projects must not fetch GitHub")
    let full = try await GitHubMentions.load(workspace: "full", repo: "LodyAI/Lody")
    assert((full["items"] as! [Any]).count == 200 && full["truncated"] as? Bool == true)
    do {
      _ = try await GitHubMentions.load(workspace: "failure", repo: "LodyAI/Lody")
      fatalError("Network failure must not masquerade as an empty connected catalog")
    } catch { assert(error.localizedDescription == "github_mentions_unavailable") }
    let after = GitHubProtocol.urls.withLock { $0.count }
    for repo in ["../repo", "LodyAI/..", "x/y?token=bad", "https://example.invalid", "LodyAI/Lody/extra"] {
      do { _ = try await GitHubMentions.load(workspace: "linked", repo: repo); fatalError("Invalid repository accepted") } catch {}
    }
    assert(GitHubProtocol.urls.withLock { $0.count } == after)
    print("GitHub mentions: Issue/PR references, unconnected project, bounded listing, credential isolation and failure behavior passed")
  }
}
