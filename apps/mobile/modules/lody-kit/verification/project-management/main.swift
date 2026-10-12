import Foundation

@MainActor enum AuthKeychain {
  static var value = "fixture-account"
  static func read() throws -> String? { value }
}
@MainActor enum GitHubCloud {
  static var calls: [(String, [String: Any])] = []
  static var owner = "owner"
  static var switchDuringAccess = false
  static func validRepository(_ repo: String) -> Bool { repo == "LodyAI/Lody" }
  static func call(_ kind: String, path: String, args: [String: Any]) async throws -> Any {
    calls.append((path, args))
    assert(args["workspaceId"] as? String == "workspace")
    switch path {
    case "localProjects:listVisibleLocalProjects":
      if switchDuringAccess { AuthKeychain.value = "different-account" }
      return [["machineId": "machine", "localProjectId": "project", "ownerUserId": owner, "sharedWithTeam": false]]
    case "github:listWorkspaceReposWithStatus": return [["repoFullName": "LodyAI/Lody", "name": "Lody", "enabled": true]]
    case "localProjects:setLocalProjectSharedWithTeam":
      assert(kind == "mutation" && args["machineId"] as? String == "machine" && args["localProjectId"] as? String == "project")
      return ["success": true, "sharedWithTeam": args["sharedWithTeam"]!]
    case "github:setRepoWorktreeSetup", "github:setRepoWorktreeCleanup":
      assert(kind == "mutation" && args["repoFullName"] as? String == "LodyAI/Lody")
      return ["updated": true]
    case "github:getAccessTokenByRepoNameForClient": return ["success": true, "token": "fixture-repository-token"]
    default: fatalError("Unexpected public operation")
    }
  }
  static func request(_ address: String, token: String? = nil, body: [String: Any]? = nil) async throws -> Any {
    assert(token == "fixture-repository-token", "Account credentials must not reach GitHub")
    if address.hasSuffix("/Lody") { return ["default_branch": "main"] }
    if address.contains("/git/trees/") { return ["sha": "head", "truncated": false, "tree": [
      ["path": ".agents/skills/review/SKILL.md", "type": "blob", "mode": "100644", "sha": "good"],
      ["path": ".agents/skills/linked/SKILL.md", "type": "blob", "mode": "120000", "sha": "link"],
      ["path": ".agents/skills/broken/SKILL.md", "type": "blob", "mode": "100644", "sha": "broken"],
    ]] }
    if address.hasSuffix("/broken") { return ["encoding": "base64", "content": "invalid"] }
    assert(address.hasSuffix("/good"))
    return ["encoding": "base64", "content": Data("---\nname: review\ndescription: >\n  Review code\n  and behavior\n---\nDo the review.".utf8).base64EncodedString()]
  }
}
@main @MainActor struct Check {
  static func main() async throws {
    let request: (String, [String: Any]) async throws -> Any = { method, values in
      try await ProjectManagementCloud.run(args: ["method": method, "args": values], workspace: "workspace", userId: "owner")
    }
    let listed = try await request("list", [:]) as! [String: Any]
    assert((listed["repos"] as! [[String: Any]]).count == 1)
    let sharing = ["machineId": "machine", "localProjectId": "project", "sharedWithTeam": true] as [String: Any]
    GitHubCloud.owner = "someone-else"
    let before = GitHubCloud.calls.count
    do { _ = try await request("share", sharing); fatalError("A teammate changed project ownership scope") } catch {}
    assert(GitHubCloud.calls.count == before + 1, "Read-only ownership check must not send a mutation")
    GitHubCloud.owner = "owner"
    _ = try await request("share", sharing)
    GitHubCloud.switchDuringAccess = true
    let beforeSwitch = GitHubCloud.calls.count
    do { _ = try await request("share", sharing); fatalError("An account switch reached a project mutation") } catch {}
    assert(GitHubCloud.calls.count == beforeSwitch + 1, "Switching account between project reads and writes must stop the write")
    GitHubCloud.switchDuringAccess = false
    AuthKeychain.value = "fixture-account"
    let config = ["scripts": ["bash": "pnpm install", "powershell": "pnpm install"], "timeoutMs": 600000] as [String: Any]
    _ = try await request("save-github-script", ["repoFullName": "LodyAI/Lody", "phase": "setup", "config": config])
    _ = try await request("save-github-script", ["repoFullName": "LodyAI/Lody", "phase": "cleanup", "config": config])
    let largeScripts = ["bash": String(repeating: "界", count: 65536), "powershell": String(repeating: "\u{1}", count: 65536)]
    _ = try await request("save-github-script", ["repoFullName": "LodyAI/Lody", "phase": "setup", "config": ["scripts": largeScripts]])
    let savedScripts = (GitHubCloud.calls.last!.1["config"] as! [String: Any])["scripts"] as! [String: String]
    assert(savedScripts == largeScripts, "Large valid Unicode and escaped scripts reach the native Cloud mutation without truncation")
    assert(!ProjectManagementCloud.validConfig(["scripts": ["bash": String(repeating: "a\u{301}", count: 32769)]]), "The native text bound matches the runtime's UTF-16 bound even for combining characters")
    assert(!ProjectManagementCloud.validConfig(["scripts": [:], "timeoutMs": true]))
    assert(!ProjectManagementCloud.validConfig(["scripts": ["bash": "x\0y"]]))
    let mutationCount = GitHubCloud.calls.count
    for values in [
      ["repoFullName": "../repo", "phase": "setup", "config": config],
      ["repoFullName": "LodyAI/Lody", "phase": "unknown", "config": config],
      ["repoFullName": "LodyAI/Lody", "phase": "setup", "config": ["scripts": ["sh": "command"]]],
    ] {
      do { _ = try await request("save-github-script", values); fatalError("Invalid remote script configuration accepted") } catch {}
    }
    assert(GitHubCloud.calls.count == mutationCount)
    let skills = try await request("github-skills", ["repoFullName": "LodyAI/Lody", "skillDirs": [".agents/skills"]]) as! [String: Any]
    let group = (skills["groups"] as! [[String: Any]])[0]
    let rows = group["skills"] as! [[String: Any]]
    assert(rows.count == 1 && rows[0]["name"] as? String == "review")
    assert(rows[0]["description"] as? String == "Review code and behavior")
    assert(group["error"] as? String == "project_skill_read_failed")
    assert(!String(describing: skills).contains("fixture-repository-token"))
    do { _ = try await request("github-skills", ["repoFullName": "LodyAI/Lody", "skillDirs": ["../skills"]]); fatalError("Invalid skill roots accepted") } catch {}
    do { _ = try await request("arbitrary-api", [:]); fatalError("Arbitrary Cloud operation accepted") } catch {}
    print("Project Cloud: owner fencing, exact public script operations, credential isolation, skill metadata and partial reads passed")
  }
}
