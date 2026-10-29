import LodyCore
import Foundation

extension CreateSessionService {
  static var live: CreateSessionService {
    var branchAttempts: [String: Int] = [:]
    return CreateSessionService(
      options: { workspaceId, projectId in
        var payload: [String: Any] = ["workspaceId": workspaceId]
        if let projectId { payload["projectId"] = projectId }
        let json = String(decoding: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(), as: UTF8.self)
        if let fixture = MentionFixture.response(json, options: true), let options = CreateJSON.decode(CreationOptions.self, fixture) {
          return options
        }
        guard let runtime = DataRuntime.current, runtime.workspace == workspaceId else {
          throw DataRuntime.failure("not_ready", String(localized: "native.runtime.sessionNotSynced", bundle: .lody))
        }
        let result = try await runtime.workspaceCall(RuntimeContract.Calls.CreationOptions.self) { workspace, _ in
          RuntimeContract.CreationOptionsParams(workspaceId: workspace, projectId: projectId)
        }
        return try JSONDecoder().decode(CreationOptions.self, from: JSONEncoder().encode(result))
      },
      repositories: { workspaceId in
        if workspaceId == "ui-home", LodyUIVerify.mentions { return ["LodyAI/FreshProject"] }
        if LodyUIVerify.enabled, workspaceId == "ui-project-picker" { return (1...20).map { "Owner/Repo\($0)" } }
        return try await GitHubCloud.repositories(workspace: workspaceId)
      },
      branches: { workspaceId, repo, page in
        if LodyUIVerify.enabled {
          let key = "\(repo):\(page)"
          branchAttempts[key, default: 0] += 1
          return try await LodyUIVerify.branches(repo: repo, page: page, attempt: branchAttempts[key] ?? 1)
        }
        return try await GitHubCloud.branches(workspace: workspaceId, repo: repo, page: page)
      },
      readPrefs: { key in
        let raw: String? = await withCheckedContinuation { continuation in
          LocalStore.queue.async { continuation.resume(returning: (try? LocalStore.shared.read(key)) ?? nil) }
        }
        return raw.flatMap { CreateJSON.decode(CreatePrefs.self, $0) }
      },
      writePrefs: { key, prefs in
        let value = CreateJSON.encode(prefs), generation = LocalStore.shared.generation
        LocalStore.queue.async { try? LocalStore.shared.write(key, value, generation: generation) }
      },
      put: { OutboxSession.shared.put(user: $0, workspace: $1, json: $2) }
    )
  }
}
