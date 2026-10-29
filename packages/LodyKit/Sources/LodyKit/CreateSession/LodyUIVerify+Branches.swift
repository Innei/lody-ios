import Foundation
import LodyCore

extension LodyUIVerify {
  static func branches(repo: String, page: Int, attempt: Int) async throws -> CreateBranches {
    try await Task.sleep(for: .milliseconds(450))
    if repo == "Owner/Repo2", attempt == 1 { throw CocoaError(.fileReadUnknown) }
    if repo == "Owner/Repo3" { return CreateBranches(names: []) }
    if page > 1 {
      return CreateBranches(names: ["feature/search-across-pages", "feature/a-long-branch-name-that-wraps-without-hiding-the-important-part"])
    }
    let branch = repo == "Owner/Repo2" ? "trunk" : "main"
    return CreateBranches(names: [branch, "develop", "fix/session-restore"], defaultBranch: branch, nextPage: 2)
  }
}
