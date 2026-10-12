import Foundation

/// Only scoped Shortcut grants enter the WebView; account credentials remain in Keychain.
@MainActor enum PromptShortcutsCloud {
  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  }
  private static let transport = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
  private struct Failure: Error { let reason: String }
  private static func fail(_ reason: String) throws -> Never { throw Failure(reason: reason) }
  private static func identifier(_ value: Any?) throws -> String {
    guard let value = value as? String, !value.isEmpty, value.count <= 200,
      value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { try fail("invalid_template") }
    return value
  }
  private static func fields(_ values: [String: Any], _ keys: Set<String>) throws {
    guard Set(values.keys) == keys else { try fail("invalid_template") }
  }
  private static func visibility(_ value: Any?) throws -> String {
    guard let value = value as? String, ["private", "workspace"].contains(value) else { try fail("invalid_template") }
    return value
  }
  private static func encode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"))!
  }
  static func run(_ method: String, args: [String: Any], workspace: String, userId: String, session: URLSession? = nil) async -> Any {
    do { return try await perform(method, args: args, workspace: workspace, userId: userId, transport: session ?? transport) }
    catch let failure as Failure { return ["shortcutError": failure.reason] }
    catch { return ["shortcutError": "offline"] }
  }
  private static func perform(_ method: String, args: [String: Any], workspace: String, userId: String, transport: URLSession) async throws -> Any {
    guard !workspace.isEmpty, !userId.isEmpty, args["workspaceId"] as? String == workspace,
      let credential = try AuthKeychain.read(), !credential.isEmpty else { try fail("permission_denied") }
    func check() throws {
      try Task.checkCancellation()
      guard try AuthKeychain.read() == credential else { try fail("permission_denied") }
    }
    var expectedStream: String?
    let kind: String
    switch method {
    case "listAccessibleDocuments":
      try fields(args, ["workspaceId"])
      kind = "query"
    case "getStreamToken":
      try fields(args, ["workspaceId", "target", "write"])
      guard let target = args["target"] as? [String: Any], let write = args["write"] as? Bool else { try fail("invalid_template") }
      if target["kind"] as? String == "index" {
        try fields(target, ["kind", "ownerUserId", "visibility"])
        let owner = try identifier(target["ownerUserId"]), visible = try visibility(target["visibility"])
        guard owner == userId || (!write && visible == "workspace") else { try fail("permission_denied") }
        expectedStream = "shortcut-index:\(encode(workspace)):\(encode(owner)):\(visible)"
      } else if target["kind"] as? String == "body" {
        try fields(target, ["kind", "bodyDocId"])
        expectedStream = "shortcut-body:\(encode(try identifier(target["bodyDocId"])))"
      } else { try fail("invalid_template") }
      kind = "action"
    case "stageDocument":
      try fields(args, ["workspaceId", "ownerUserId", "shortcutId", "bodyDocId", "visibility"])
      guard try identifier(args["ownerUserId"]) == userId else { try fail("permission_denied") }
      _ = try identifier(args["shortcutId"]); _ = try identifier(args["bodyDocId"]); _ = try visibility(args["visibility"])
      kind = "mutation"
    case "activateDocument":
      try fields(args, ["workspaceId", "bodyDocId", "previousBodyDocId", "previousRevision", "revision", "slug", "indexBytes"])
      _ = try identifier(args["bodyDocId"]); _ = try identifier(args["revision"])
      for key in ["previousBodyDocId", "previousRevision"] { if !(args[key] is NSNull) { _ = try identifier(args[key]) } }
      guard let slug = args["slug"] as? String, slug.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil,
        let bytes = args["indexBytes"] as? Int, bytes > 0, bytes <= 8 * 1024 else { try fail("invalid_template") }
      kind = "mutation"
    case "settleDocument", "revokeShortcut":
      try fields(args, ["workspaceId", "shortcutId", "bodyDocId", "visibility"])
      _ = try identifier(args["shortcutId"]); _ = try identifier(args["bodyDocId"]); _ = try visibility(args["visibility"])
      kind = "mutation"
    default: try fail("invalid_template")
    }
    let auth = try await request("https://backend.lody.ai/api/auth/convex/token", credential: credential, transport: transport)
    try check()
    guard let auth = auth as? [String: Any], let jwt = auth["token"] as? String, !jwt.isEmpty else { try fail("permission_denied") }
    let response = try await request("https://convex.lody.ai/api/\(kind)", credential: jwt, body: [
      "path": "promptShortcuts:\(method)", "format": "convex_encoded_json", "args": [args]
    ], transport: transport)
    try check()
    guard let response = response as? [String: Any] else { try fail("invalid_template") }
    if response["status"] as? String != "success" {
      let message = (response["errorMessage"] as? String ?? "").lowercased()
      if message.contains("forbidden") || message.contains("permission") || message.contains("unauth") || message.contains("member") { try fail("permission_denied") }
      if message.contains("conflict") || message.contains("changed") || message.contains("already") || message.contains("revision") { try fail("conflict") }
      if message.contains("limit") || message.contains("quota") { try fail("size_limit") }
      try fail("unavailable")
    }
    guard let value = response["value"] else { try fail("invalid_template") }
    if let expectedStream {
      guard let grant = value as? [String: Any], grant["streamId"] as? String == expectedStream,
        let token = grant["token"] as? String, !token.isEmpty, token.utf8.count <= 16384,
        let expiry = grant["expiresIn"] as? Double, expiry.isFinite, expiry > 0,
        let address = grant["gatewayBaseUrl"] as? String, let url = URL(string: address),
        url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { try fail("permission_denied") }
    }
    if method == "listAccessibleDocuments" {
      guard let rows = value as? [[String: Any]], rows.count <= 10000 else { try fail("invalid_template") }
      for row in rows {
        _ = try identifier(row["shortcutId"]); _ = try identifier(row["bodyDocId"])
        let owner = try identifier(row["ownerUserId"]), visible = try visibility(row["visibility"])
        guard visible == "workspace" || owner == userId else { try fail("permission_denied") }
      }
    }
    return value
  }
  private static func request(_ address: String, credential: String, body: [String: Any]? = nil, transport: URLSession) async throws -> Any {
    var request = URLRequest(url: URL(string: address)!, timeoutInterval: 30)
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (file, response) = try await transport.download(for: request)
    defer { try? FileManager.default.removeItem(at: file) }
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else { try fail("offline") }
    if response.statusCode == 401 || response.statusCode == 403 { try fail("permission_denied") }
    guard (200..<300).contains(response.statusCode) else { try fail("offline") }
    guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024 else { try fail("size_limit") }
    return try JSONSerialization.jsonObject(with: Data(contentsOf: file))
  }
}
