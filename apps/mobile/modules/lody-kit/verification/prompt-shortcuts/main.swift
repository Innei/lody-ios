import Foundation
import os

enum AuthKeychain {
  static let credential = OSAllocatedUnfairLock(initialState: "synthetic-credential")
  static func read() throws -> String? { credential.withLock { $0 } }
}
final class ShortcutProtocol: URLProtocol {
  static let calls = OSAllocatedUnfairLock(initialState: [String]())
  static let wrongStream = OSAllocatedUnfairLock(initialState: false)
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let host = request.url!.host!
    Self.calls.withLock { $0.append(host) }
    var response: [String: Any]
    if host == "backend.lody.ai" {
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-credential")
      response = ["token": "synthetic-jwt"]
    } else {
      precondition(host == "convex.lody.ai" && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-jwt")
      var bytes = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
      }
      let payload = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
      let path = payload["path"] as! String
      let args = (payload["args"] as! [[String: Any]])[0]
      precondition(args["workspaceId"] as? String == "workspace")
      switch path {
      case "promptShortcuts:listAccessibleDocuments":
        precondition(request.url!.path == "/api/query")
        response = ["status": "success", "value": [["shortcutId": "shortcut", "bodyDocId": "body", "ownerUserId": "user", "visibility": "private", "revision": "revision"]]]
      case "promptShortcuts:getStreamToken":
        precondition(request.url!.path == "/api/action")
        let id = Self.wrongStream.withLock { $0 } ? "workspace:meta" : "shortcut-index:workspace:user:private"
        response = ["status": "success", "value": ["token": "scoped-token", "expiresIn": 60, "gatewayBaseUrl": "https://gateway.lody.ai", "streamId": id]]
      case "promptShortcuts:revokeShortcut":
        precondition(request.url!.path == "/api/mutation")
        response = ["status": "error", "errorMessage": "forbidden"]
      default: fatalError("Unexpected cloud method")
      }
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@main @MainActor struct Check {
  static func main() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ShortcutProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let list = await PromptShortcutsCloud.run("listAccessibleDocuments", args: ["workspaceId": "workspace"], workspace: "workspace", userId: "user", session: session)
    precondition((list as? [[String: Any]])?.count == 1)
    let before = ShortcutProtocol.calls.withLock { $0.count }
    let foreign = await PromptShortcutsCloud.run("listAccessibleDocuments", args: ["workspaceId": "other"], workspace: "workspace", userId: "user", session: session) as! [String: String]
    precondition(foreign["shortcutError"] == "permission_denied")
    let arbitrary = await PromptShortcutsCloud.run("deleteAll", args: ["workspaceId": "workspace"], workspace: "workspace", userId: "user", session: session) as! [String: String]
    precondition(arbitrary["shortcutError"] == "invalid_template")
    let foreignIndex = await PromptShortcutsCloud.run("getStreamToken", args: ["workspaceId": "workspace", "write": false, "target": ["kind": "index", "ownerUserId": "other", "visibility": "private"]], workspace: "workspace", userId: "user", session: session) as! [String: String]
    precondition(foreignIndex["shortcutError"] == "permission_denied")
    precondition(ShortcutProtocol.calls.withLock { $0.count } == before, "Invalid requests must never reach the network")
    let args: [String: Any] = ["workspaceId": "workspace", "write": false, "target": ["kind": "index", "ownerUserId": "user", "visibility": "private"]]
    let grant = await PromptShortcutsCloud.run("getStreamToken", args: args, workspace: "workspace", userId: "user", session: session) as! [String: Any]
    precondition(grant["token"] as? String == "scoped-token")
    precondition(grant["streamId"] as? String == "shortcut-index:workspace:user:private")
    ShortcutProtocol.wrongStream.withLock { $0 = true }
    let wrong = await PromptShortcutsCloud.run("getStreamToken", args: args, workspace: "workspace", userId: "user", session: session) as! [String: String]
    precondition(wrong["shortcutError"] == "permission_denied", "Workspace-wide grants cannot masquerade as scoped grants")
    let rejected = await PromptShortcutsCloud.run("revokeShortcut", args: ["workspaceId": "workspace", "shortcutId": "shortcut", "bodyDocId": "body", "visibility": "private"], workspace: "workspace", userId: "user", session: session) as! [String: String]
    precondition(rejected["shortcutError"] == "permission_denied")
    precondition(ShortcutProtocol.calls.withLock { $0.count } == before + 6, "Each operation runs once, with no mutation replay")
    print("Prompt Shortcuts native boundary passed: native credentials, exact scoped grants, allowlisted operations, identity fences and no mutation replay")
  }
}
