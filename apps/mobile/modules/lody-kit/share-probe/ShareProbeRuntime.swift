import Foundation
import WebKit

@MainActor
final class ShareProbeRuntime: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  struct Workspace: Decodable {
    let id: String
    let name: String
  }
  var onAgents: ([ShareProbeAgent]) -> Void = { _ in }
  var onFailure: () -> Void = {}
  private(set) var userId = ""
  private var workspaceId = ""
  private var webView: WKWebView?
  private var grantTask: Task<Void, Never>?
  private var timer: Timer?
  private var startedAt: TimeInterval = 0
  private var health = RuntimeHealth()
  private var pingPending = false
  private var optionsPending = false
  private var hasOptions = false
  private var commands: [UUID: CheckedContinuation<[String: Any], Error>] = [:]

  private static func error() -> Error { NSError(domain: "LodyShareProbe", code: 1) }

  /// Long-lived credentials stay in native Keychain/URLSession, outside the WebView.
  private func readToken() throws -> String {
    guard let token = try AuthKeychain.read(), !token.isEmpty else { throw Self.error() }
    return token
  }

  private func request(_ path: String, token: String, body: [String: String]? = nil) async throws -> Data {
    var request = URLRequest(url: URL(string: "https://backend.lody.ai/api/" + path)!, timeoutInterval: 15)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1024 * 1024 else { throw Self.error() }
    return data
  }

  func authenticate() async throws -> [Workspace] {
    let token = try readToken()
    let data = try await request("auth/get-session", token: token)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let user = object["user"] as? [String: Any], let id = user["id"] as? String, !id.isEmpty else { throw Self.error() }
    userId = id
    return try JSONDecoder().decode([Workspace].self, from: await request("auth/organization/list", token: token))
  }

  func validateAccount() async throws {
    let data = try await request("auth/get-session", token: readToken())
    let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard (value?["user"] as? [String: Any])?["id"] as? String == userId else { throw Self.error() }
  }

  func start(workspaceId: String) throws {
    stop()
    self.workspaceId = workspaceId
    guard !workspaceId.isEmpty, !userId.isEmpty,
      let resource = Bundle.main.url(forResource: "DataRuntime", withExtension: "html") else { throw Self.error() }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.userContentController.add(self, name: "dataRuntime")
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    webView = view
    startedAt = ProcessInfo.processInfo.systemUptime
    health = RuntimeHealth()
    health.started(at: startedAt)
    view.loadHTMLString(try String(contentsOf: resource, encoding: .utf8), baseURL: URL(string: "https://lody.ai/"))
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      MainActor.assumeIsolated { self.tick() }
    }
  }

  func stop() {
    timer?.invalidate(); timer = nil
    grantTask?.cancel(); grantTask = nil
    let view = webView
    webView = nil
    view?.configuration.userContentController.removeScriptMessageHandler(forName: "dataRuntime")
    view?.navigationDelegate = nil
    view?.stopLoading()
    for continuation in commands.values { continuation.resume(throwing: Self.error()) }
    commands.removeAll()
    pingPending = false; optionsPending = false; hasOptions = false
  }

  private func fail() { stop(); onFailure() }

  private func tick() {
    let now = ProcessInfo.processInfo.systemUptime
    guard !health.timedOut(at: now), hasOptions || now - startedAt < 45 else { fail(); return }
    guard health.ready, !pingPending, let view = webView else { return }
    pingPending = true
    view.callAsyncJavaScript("return globalThis.dataRuntime.ping()", arguments: [:], in: nil, in: .page) { [weak self, weak view] result in
      guard let self, let view, self.webView === view else { return }
      self.pingPending = false
      if case .success = result { self.health.acknowledged(at: ProcessInfo.processInfo.systemUptime) }
    }
  }

  func command(_ method: String, _ args: [String: Any]) async throws -> [String: Any] {
    guard let view = webView, health.ready else { throw Self.error() }
    return try await withCheckedThrowingContinuation { continuation in
      let id = UUID()
      commands[id] = continuation
      DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self, weak view] in
        guard let self, let view, self.webView === view, self.commands[id] != nil else { return }
        self.fail() // Never restart or replay a command after its outcome becomes uncertain.
      }
      view.callAsyncJavaScript(
        "const result = await globalThis.dataRuntime[method](args); return JSON.stringify(method === 'ensureSession' ? { state: result } : result)",
        arguments: ["method": method, "args": args], in: nil, in: .page
      ) { [weak self, weak view] result in
        guard let self, let view, self.webView === view, let pending = self.commands.removeValue(forKey: id) else { return }
        do {
          guard let json = try result.get() as? String, let data = json.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Self.error() }
          pending.resume(returning: object)
        } catch { pending.resume(throwing: Self.error()) }
      }
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let view = webView, message.webView === view,
      let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
    switch type {
    case "ready":
      guard !health.ready else { return }
      health.acknowledged(at: ProcessInfo.processInfo.systemUptime)
      view.callAsyncJavaScript("globalThis.dataRuntime.start(workspace)", arguments: ["workspace": workspaceId], in: nil, in: .page, completionHandler: nil)
    case "grant":
      guard grantTask == nil else { return }
      grantTask = Task { [weak self, weak view] in
        guard let self, let view else { return }
        do {
          // Reject an account switch while the extension is open.
          let token = try self.readToken()
          let account = try await self.request("auth/get-session", token: token)
          let value = try JSONSerialization.jsonObject(with: account) as? [String: Any]
          guard (value?["user"] as? [String: Any])?["id"] as? String == self.userId else { throw Self.error() }
          let data = try await self.request("loro-streams/token", token: token, body: ["workspaceId": self.workspaceId])
          guard self.webView === view, !Task.isCancelled else { return }
          guard let grant = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = grant["token"] as? String, !token.isEmpty,
            let address = grant["gatewayBaseUrl"] as? String, let url = URL(string: address),
            url.scheme == "https", url.user == nil, url.password == nil,
            let expiry = grant["expiresIn"] as? Double, expiry > 0 else { throw Self.error() }
          view.callAsyncJavaScript("globalThis.dataRuntime.grant(value)", arguments: ["value": ["token": token, "gatewayBaseUrl": address, "expiresIn": expiry]], in: nil, in: .page, completionHandler: nil)
          self.grantTask = nil
        } catch {
          guard self.webView === view, !Task.isCancelled else { return }
          self.fail()
        }
      }
    case "synced":
      guard !optionsPending, !hasOptions else { return }
      optionsPending = true
      Task { [weak self, weak view] in
        guard let self, let view else { return }
        do {
          let options = try await self.command("creationOptions", ["workspaceId": self.workspaceId])
          guard self.webView === view else { return }
          let data = try JSONSerialization.data(withJSONObject: options["agents"] ?? [])
          let agents = try JSONDecoder().decode([ShareProbeAgent].self, from: data)
          self.hasOptions = true; self.optionsPending = false
          self.onAgents(agents)
        } catch {
          if self.webView === view { self.fail() }
        }
      }
    case "syncError": fail()
    default: break // No transcript, token or catalog content is logged or persisted.
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
    let address = navigationAction.request.url?.absoluteString
    let local = navigationAction.navigationType == .other && (address == "about:blank" || address == "https://lody.ai/")
    decisionHandler(local ? .allow : .cancel)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if self.webView === webView { fail() } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView { fail() } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView { fail() } }
}
