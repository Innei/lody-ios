import UIKit

@MainActor
final class ShareSubmission {
  var onStatus: (String) -> Void = { _ in }
  private let session: URLSession
  init(session: URLSession = .shared) { self.session = session }

  private func request(_ path: String, token: String, body: [String: Any]? = nil) async throws -> (Int, [String: Any]) {
    try Task.checkCancellation()
    var request = URLRequest(url: URL(string: "https://backend.lody.ai/api/" + path)!, timeoutInterval: 20)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, data.count <= 256 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
    return (response.statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
  }
  func authenticate(user: String) async throws -> String {
    guard let token = try AuthKeychain.read() else { throw SessionAttachments.error(LodyStrings.text("native.create.signInBefore")) }
    let (status, account) = try await request("auth/get-session", token: token)
    guard status == 200, (account["user"] as? [String: Any])?["id"] as? String == user else {
      throw SessionAttachments.error(LodyStrings.text("native.create.accountChanged"))
    }
    return token
  }
  func submit(_ draft: [String: Any]) async throws -> [String: Any] {
    guard let token = try AuthKeychain.read() else { throw SessionAttachments.error(LodyStrings.text("native.create.signInBefore")) }
    let requestID = UUID().uuidString.lowercased()
    let saved = try ShareStore.authenticated(token) {
      let snapshot = ShareStore.snapshot()
      guard snapshot["userId"] as? String == draft["userId"] as? String,
        snapshot["workspaceId"] as? String == draft["workspaceId"] as? String else { throw CocoaError(.userCancelled) }
      return try ShareStore.saveDraft(draft, request: requestID)
    }
    return try await resume(saved)
  }
  func resume(_ saved: [String: Any]) async throws -> [String: Any] {
    guard let requestID = saved["requestId"] as? String, let user = saved["userId"] as? String,
      let workspace = saved["workspaceId"] as? String else { throw CocoaError(.fileReadCorruptFile) }
    let token = try await authenticate(user: user)
    let sessionID = ShareStore.sessionID(user: user, workspace: workspace, request: requestID)
    let receiptURL = try ShareStore.receiptURL(requestID)
    var receipt = saved
    let base = "workspaces/\(SessionAttachments.segment(workspace))/session-submissions"
    var body = receipt["body"] as? [String: Any]
    if body == nil {
      onStatus(LodyStrings.text("native.create.uploading"))
      var temporary: [[String: Any]] = []
      var temporaryURLs: [URL] = []
      defer { for url in temporaryURLs { try? FileManager.default.removeItem(at: url) } }
      for var attachment in receipt["attachments"] as? [[String: Any]] ?? [] {
        guard let uri = attachment["uri"] as? String, let source = URL(string: uri),
          source.resolvingSymlinksInPath().path.hasPrefix(receiptURL.deletingLastPathComponent().path + "/files/"),
          let copy = ChatAttachment.store(source) else { throw CocoaError(.fileReadNoSuchFile) }
        attachment["uri"] = copy.absoluteString; temporary.append(attachment); temporaryURLs.append(copy)
      }
      let uploaded = try await SessionAttachments.uploadJSON(JSONSerialization.data(withJSONObject: temporary), workspace: workspace, session: sessionID, expectedToken: token)
      guard let attachments = try JSONSerialization.jsonObject(with: uploaded) as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
      body = try Self.body(receipt, request: requestID, attachments: attachments)
      receipt["body"] = body; receipt["phase"] = "confirming"; receipt["sessionId"] = sessionID
      // A lost POST response is recovered with this exact body and request ID.
      try ShareStore.authenticated(token) { try ShareStore.write(receipt, to: receiptURL) }
    }
    guard try AuthKeychain.read() == token else { throw SessionAttachments.error(LodyStrings.text("native.create.accountChangedCheck")) }
    onStatus(LodyStrings.text("native.create.submitting"))
    let (lookupStatus, previous) = try await request(base + "/" + requestID, token: token)
    var status = lookupStatus
    var result = previous
    if lookupStatus == 404 {
      (status, result) = try await request(base, token: token, body: body)
    }
    guard status == 200 || status == 202 else { throw SessionAttachments.error(LodyStrings.text("native.create.confirmError")) }
    for _ in 0..<12 {
      if result["state"] as? String != "pending" { break }
      onStatus(LodyStrings.text("native.create.saving"))
      try await Task.sleep(for: .seconds(1))
      guard try AuthKeychain.read() == token else { throw SessionAttachments.error(LodyStrings.text("native.create.accountChangedShort")) }
      (status, result) = try await request(base + "/" + requestID, token: token)
      guard status == 200 else { throw SessionAttachments.error(LodyStrings.text("native.create.savedCheck")) }
    }
    if result["state"] as? String == "submitted" {
      try ShareStore.authenticated(token) {
      try ShareStore.write(["requestId": requestID, "sessionId": sessionID, "userId": user,
        "workspaceId": workspace, "phase": "submitted"], to: receiptURL)
      let files = receiptURL.deletingLastPathComponent().appendingPathComponent("files")
      if FileManager.default.fileExists(atPath: files.path) { try? FileManager.default.removeItem(at: files) }
      }
    }
    return result
  }
  static func body(_ draft: [String: Any], request: String, attachments: [[String: Any]]) throws -> [String: Any] {
    guard let agent = draft["agent"] as? [String: Any], let machine = agent["machineId"] as? String else { throw CocoaError(.fileReadCorruptFile) }
    let text = draft["text"] as? String ?? ""
    var blocks = attachments
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.insert(["type": "text", "text": text], at: 0) }
    var body: [String: Any] = ["requestId": request, "machineId": machine, "agentConfigId": agent["id"] ?? "",
      "cliType": agent["cliType"] ?? "builtin", "agentType": agent["agentType"] ?? "", "title": draft["title"] ?? LodyStrings.text("native.create.title"),
      "prompt": text, "inputBlocks": blocks]
    let project = draft["projectId"] as? String ?? ""
    if project.hasPrefix("github:") {
      body["project"] = ["kind": "github", "repoFullName": String(project.dropFirst(7)), "branch": draft["branch"] as? String ?? ""]
    } else if !project.isEmpty {
      let prefix = machine + ":local:"
      guard project.hasPrefix(prefix) else { throw CocoaError(.fileReadCorruptFile) }
      body["project"] = ["kind": "local", "localProjectId": String(project.dropFirst(prefix.count))]
    }
    let choice = draft["choice"] as? [String: Any] ?? [:]
    body["modelId"] = choice["modelId"]; body["modeId"] = choice["modeId"]
    var values = choice["configOptionValues"] as? [String: Any] ?? [:]
    if let effort = choice["effort"] as? String, let key = choice["reasoningEffortConfigId"] as? String { values[key] = effort }
    body["configOptionValues"] = values
    return body
  }
}

/// Both hosts offer the same explicit recovery action; no automatic replay.
@MainActor
final class ShareRecovery {
  private var task: Task<Void, Never>?
  func cancel() { task?.cancel(); task = nil }
  func present(on form: CreateSessionController, onResult: @escaping ([String: Any]) -> Void) {
    let pending = ShareStore.pending(user: form.form.userID, workspace: form.form.workspaceID)
    let alert = UIAlertController(title: LodyStrings.text("native.create.previousPlural"), message: LodyStrings.text("native.create.checkExplanation"), preferredStyle: .actionSheet)
    for receipt in pending {
      alert.addAction(UIAlertAction(title: receipt["title"] as? String ?? LodyStrings.text("native.create.checkSubmission"), style: .default) { [weak self, weak form] _ in
        guard let self, let form else { return }
        form.busy = true
        self.task = Task { [weak form] in
          guard let form else { return }
          let transport = ShareSubmission()
          transport.onStatus = { [weak form] in form?.notice = $0 }
          do {
            let result = try await transport.resume(receipt)
            try Task.checkCancellation()
            form.busy = false; onResult(result)
          } catch {
            form.busy = false
            if !Task.isCancelled { form.notice = error.localizedDescription }
          }
        }
      })
    }
    alert.addAction(UIAlertAction(title: LodyStrings.text("native.create.cancel"), style: .cancel))
    alert.popoverPresentationController?.sourceView = form.view
    alert.popoverPresentationController?.sourceRect = form.view.bounds
    form.present(alert, animated: true)
  }
  static func notice(_ result: [String: Any]) -> String {
    switch result["state"] as? String {
    case "submitted": return LodyStrings.text("native.create.submitted")
    case "pending": return LodyStrings.text("native.create.pending")
    default: return LodyStrings.text("native.create.unconfirmed")
    }
  }
}
