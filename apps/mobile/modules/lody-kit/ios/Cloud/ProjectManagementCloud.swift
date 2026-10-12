import Foundation

/// Project Cloud operations and GitHub tokens stay behind the existing Keychain boundary.
@MainActor enum ProjectManagementCloud {
  static func run(args: [String: Any], workspace: String, userId: String) async throws -> Any {
    guard !workspace.isEmpty, !userId.isEmpty, let method = args["method"] as? String,
          let values = args["args"] as? [String: Any] else { throw failure() }
    guard let credential = try AuthKeychain.read(), !credential.isEmpty else { throw failure() }
    func check() throws {
      try Task.checkCancellation()
      guard try AuthKeychain.read() == credential else { throw failure() }
    }
    func call(_ kind: String, path: String, args: [String: Any]) async throws -> Any {
      try check()
      let value = try await GitHubCloud.call(kind, path: path, args: args)
      try check()
      return value
    }
    switch method {
    case "list":
      let access = try await call("query", path: "localProjects:listVisibleLocalProjects", args: ["workspaceId": workspace])
      let repos = try await call("query", path: "github:listWorkspaceReposWithStatus", args: ["workspaceId": workspace])
      guard let access = access as? [[String: Any]],
            repos is NSNull || repos is [[String: Any]] else { throw failure() }
      return ["access": access, "repos": repos is NSNull ? [] : repos]
    case "share":
      guard let machineId = values["machineId"] as? String, validId(machineId),
            let projectId = values["localProjectId"] as? String, validId(projectId),
            let shared = values["sharedWithTeam"] as? Bool,
            let access = try await call("query", path: "localProjects:listVisibleLocalProjects", args: ["workspaceId": workspace]) as? [[String: Any]],
            access.contains(where: { $0["machineId"] as? String == machineId && $0["localProjectId"] as? String == projectId && $0["ownerUserId"] as? String == userId })
      else { throw failure() }
      let result = try await call("mutation", path: "localProjects:setLocalProjectSharedWithTeam", args: [
        "workspaceId": workspace, "machineId": machineId, "localProjectId": projectId, "sharedWithTeam": shared,
      ])
      guard let result = result as? [String: Any], result["success"] as? Bool == true,
            result["sharedWithTeam"] as? Bool == shared else { throw failure() }
      return result
    case "save-github-script":
      guard let repo = values["repoFullName"] as? String, GitHubCloud.validRepository(repo),
            let phase = values["phase"] as? String, ["setup", "cleanup"].contains(phase),
            let config = values["config"] as? [String: Any], validConfig(config) else { throw failure() }
      let path = phase == "setup" ? "github:setRepoWorktreeSetup" : "github:setRepoWorktreeCleanup"
      let result = try await call("mutation", path: path, args: [
        "workspaceId": workspace, "repoFullName": repo, "config": config,
      ])
      guard let result = result as? [String: Any], result["updated"] as? Bool == true else { throw failure() }
      return result
    case "github-skills":
      guard let repo = values["repoFullName"] as? String, GitHubCloud.validRepository(repo),
            let dirs = values["skillDirs"] as? [String], dirs.count <= 100,
            dirs.allSatisfy(validRelativePath) else { throw failure() }
      try check()
      let result = try await githubSkills(workspace: workspace, repo: repo, dirs: dirs)
      try check()
      return result
    default: throw failure()
    }
  }

  private static func validId(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 1024 && value.rangeOfCharacter(from: .controlCharacters) == nil
  }
  static func validConfig(_ config: [String: Any]) -> Bool {
    guard Set(config.keys).isSubset(of: ["scripts", "timeoutMs"]), let scripts = config["scripts"] as? [String: String],
          Set(scripts.keys).isSubset(of: ["bash", "powershell"]),
          scripts.values.allSatisfy({ $0.utf16.count <= 65536 && !$0.contains("\0") }) else { return false }
    if let timeout = config["timeoutMs"] {
      guard let number = timeout as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue > 0, number.doubleValue <= 9007199254740991,
            number.doubleValue.rounded(.towardZero) == number.doubleValue else { return false }
    }
    return true
  }
  private static func validRelativePath(_ value: String) -> Bool {
    validId(value) && !value.hasPrefix("/") && !value.contains("\\") &&
      value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }
  private static func segment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
  }
  private struct SkillFile: Sendable {
    let path: String
    let content: String?
  }
  private static func readSkill(repo: String, sha: String, path: String, token: String) async -> SkillFile {
    do {
      guard let blob = try await GitHubCloud.request("https://api.github.com/repos/\(repo)/git/blobs/\(segment(sha))", token: token) as? [String: Any],
            blob["encoding"] as? String == "base64", let encoded = blob["content"] as? String,
            let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), bytes.count <= 256 * 1024,
            let content = String(data: bytes, encoding: .utf8) else { return SkillFile(path: path, content: nil) }
      return SkillFile(path: path, content: content)
    } catch { return SkillFile(path: path, content: nil) }
  }
  private static func githubSkills(workspace: String, repo: String, dirs: [String]) async throws -> [String: Any] {
    let account = try AuthKeychain.read()
    guard let grant = try await GitHubCloud.call("action", path: "github:getAccessTokenByRepoNameForClient", args: [
      "workspaceId": workspace, "repoFullName": repo,
    ]) as? [String: Any], grant["success"] as? Bool == true,
      let token = grant["token"] as? String, !token.isEmpty,
      let repository = try await GitHubCloud.request("https://api.github.com/repos/\(repo)", token: token) as? [String: Any],
      let branch = repository["default_branch"] as? String, !branch.isEmpty,
      let tree = try await GitHubCloud.request("https://api.github.com/repos/\(repo)/git/trees/\(segment(branch))?recursive=1", token: token) as? [String: Any],
      let rows = tree["tree"] as? [[String: Any]] else { throw failure() }
    let candidates = rows.compactMap { row -> (String, String)? in
      guard row["type"] as? String == "blob", row["mode"] as? String != "120000",
            let path = row["path"] as? String, validRelativePath(path), path.hasSuffix("/SKILL.md"),
            dirs.contains(where: { path.hasPrefix($0 + "/") }),
            let sha = row["sha"] as? String, validId(sha) else { return nil }
      return (path, sha)
    }.sorted { $0.0 < $1.0 }
    var files: [SkillFile] = []
    // shortcut: bound one scan to 256 files and 2 MiB; expose partial results and refresh when the catalog grows.
    let selected = Array(candidates.prefix(256))
    for start in stride(from: 0, to: selected.count, by: 4) {
      try Task.checkCancellation()
      let batch = Array(selected[start..<min(start + 4, selected.count)])
      let values = await withTaskGroup(of: SkillFile.self) { group in
        for (path, sha) in batch {
          group.addTask { await readSkill(repo: repo, sha: sha, path: path, token: token) }
        }
        var values: [SkillFile] = []
        for await value in group { values.append(value) }
        return values
      }
      files.append(contentsOf: values)
    }
    var groups: [[String: Any]] = []
    var budget = 2 * 1024 * 1024
    for dir in dirs {
      let matches = files.filter { $0.path.hasPrefix(dir + "/") }.sorted { $0.path < $1.path }
      if matches.isEmpty { continue }
      var skills: [[String: Any]] = []
      var partial = tree["truncated"] as? Bool == true || candidates.count > selected.count
      var unreadable = false
      for file in matches {
        guard let content = file.content else { unreadable = true; continue }
        budget -= content.utf8.count
        if budget < 0 { partial = true; break }
        let fallback = file.path.split(separator: "/").dropLast().last.map(String.init) ?? file.path
        var skill: [String: Any] = [
          "id": file.path, "name": fallback, "relativePath": file.path, "isSymlink": false, "content": content,
        ]
        for (key, value) in metadata(content) { skill[key] = value }
        skills.append(skill)
      }
      var group: [String: Any] = ["scope": "project", "dir": dir, "skills": skills, "truncated": partial]
      if unreadable { group["error"] = "project_skill_read_failed" }
      groups.append(group)
    }
    if groups.isEmpty, tree["truncated"] as? Bool == true {
      groups.append(["scope": "project", "dir": "", "skills": [], "truncated": true])
    }
    try Task.checkCancellation()
    guard try AuthKeychain.read() == account else { throw failure() }
    return ["groups": groups, "contentFingerprint": tree["sha"] as? String ?? ""]
  }

  static func metadata(_ content: String) -> [String: String] {
    let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    guard lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }), end <= 512 else { return [:] }
    var result: [String: String] = [:]
    var index = 1
    while index < end {
      let line = lines[index], parts = line.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      index += 1
      guard parts.count == 2, ["name", "description", "version", "author"].contains(String(parts[0])) else { continue }
      var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
      if ["|", "|-", "|+", ">", ">-", ">+"].contains(value) {
        let folded = value.hasPrefix(">")
        var block: [String] = []
        while index < end, lines[index].hasPrefix(" ") || lines[index].isEmpty {
          block.append(lines[index].trimmingCharacters(in: .whitespaces)); index += 1
        }
        value = block.joined(separator: folded ? " " : "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      } else if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
        value = String(value.dropFirst().dropLast())
      }
      if !value.isEmpty { result[String(parts[0])] = value }
    }
    return result
  }
  private static func failure() -> NSError {
    NSError(domain: "LodyKit.ProjectManagement", code: 1, userInfo: [NSLocalizedDescriptionKey: "project_cloud_unavailable"])
  }
}
