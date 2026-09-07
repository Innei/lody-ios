import ExpoModulesCore
import WebKit
import UIKit

// The owner lives in Swift, so a wedged JS event loop cannot disable its watchdog.
final class DataRuntime: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private var webView: WKWebView?
  private var sessionId: String?
  private var retainedSessions: [String] = []
  private var userId = ""
  private let localStore: LocalStore
  private var cacheErrorShown = false
  private var commands: [UUID: Promise] = [:]
  private var timer: Timer?
  private var attachmentTask: Task<Void, Never>?
  private var grantTask: URLSessionDataTask?
  private var health = RuntimeHealth()
  private var pingPending = false
  private var workspace: String?
  private var owner = ""
  private var generation = 0
  private var backgrounded = false
  private var phase = "stopped"
  private var reason = ""
  private var lastStartReason = ""
  private var acknowledgements = 0
  private var observers: [NSObjectProtocol] = []
  private let emit: ([String: Any]) -> Void
  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  init(localStore: LocalStore, emit: @escaping ([String: Any]) -> Void) {
    self.localStore = localStore
    self.emit = emit
    super.init()
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.workspace != nil else { return }
      self.backgrounded = true
      self.health.suspend()
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
      ContentStore.shared.clearAll()
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.workspace != nil, self.backgrounded else { return }
      self.backgrounded = false
      self.health.resume(at: self.now)
      self.pingPending = false
      if self.webView == nil { self.build(reason: "foreground") }
      else { self.tick() }
    })
  }
  func start(workspace: String, owner: String, userId: String) {
    disposeView()
    if self.workspace != workspace || self.userId != userId { sessionId = nil; retainedSessions = [] }
    self.userId = userId; cacheErrorShown = false
    self.workspace = workspace; self.owner = owner; health = RuntimeHealth()
    backgrounded = UIApplication.shared.applicationState == .background
    if backgrounded { publish("background", reason: "paused") }
    else { build(reason: "subscribe") }
  }
  func stop(owner: String? = nil) {
    if let owner, self.owner != owner { return }
    workspace = nil; sessionId = nil; retainedSessions = []; userId = ""; disposeView(); publish("stopped", reason: "unsubscribe")
  }
  func status() -> [String: Any] {
    var value: [String: Any] = ["owner": owner, "generation": generation, "state": phase, "reason": reason, "acknowledgements": acknowledgements, "lastStartReason": lastStartReason]
    #if DEBUG
    if backgroundProbe {
      value["probeBackgroundUpdates"] = probeBackgroundUpdates
      value["probeUpdates"] = probeUpdates
      if #available(iOS 26.0, *) {
        value["backgroundTaskState"] = ContinuedSessionTasks.shared.debugState
        value["backgroundTaskCount"] = ContinuedSessionTasks.shared.debugCount
      }
    }
    #endif
    return value
  }
  private func publish(_ state: String, reason: String, extra: [String: Any] = [:]) {
    self.phase = state; self.reason = reason
    emit(status().merging(extra, uniquingKeysWith: { _, new in new }))
  }
  private func build(reason: String) {
    guard workspace != nil else { return }
    disposeView(); lastStartReason = reason; generation += 1; health.started(at: now); acknowledgements = 0
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController.add(self, name: "dataRuntime")
    let view = WKWebView(frame: .zero, configuration: config)
    #if DEBUG
    if #available(iOS 16.4, *) { view.isInspectable = true }
    #endif
    view.navigationDelegate = self
    webView = view
    publish("starting", reason: reason)
    timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    #if DEBUG
    if backgroundProbe {
      view.loadHTMLString(Self.backgroundProbeHTML, baseURL: URL(string: "https://lody.ai"))
      return
    }
    #endif
    do {
      guard let url = Bundle(for: LodyKitModule.self).url(forResource: "DataRuntime", withExtension: "html") ?? Bundle.main.url(forResource: "DataRuntime", withExtension: "html") else { throw NSError(domain: "MissingDataRuntime", code: 1) }
      // A bundled document with the official site's origin; no remote scripts are loaded.
      view.loadHTMLString(try String(contentsOf: url, encoding: .utf8), baseURL: URL(string: "https://lody.ai"))
    } catch { disposeView(); publish("failed", reason: "missing_resource") }
  }
  private func disposeView() {
    if #available(iOS 26.0, *) { ContinuedSessionTasks.shared.finishAll(owner: owner) }
    attachmentTask?.cancel(); attachmentTask = nil
    for promise in commands.values { fail(promise, "runtime_replaced", "通信层已重建，发送结果请以同步记录为准") }; commands.removeAll()
    timer?.invalidate(); timer = nil
    grantTask?.cancel(); grantTask = nil
    pingPending = false
    let old = webView; webView = nil
    old?.configuration.userContentController.removeScriptMessageHandler(forName: "dataRuntime")
    old?.navigationDelegate = nil
    old?.stopLoading()
  }
  private func recover(_ reason: String) {
    guard workspace != nil else { return }
    if backgrounded { disposeView(); publish("background", reason: reason); return }
    if health.allowRestart(at: now) { build(reason: reason) }
    else { disposeView(); publish("failed", reason: "restart_limit") }
  }
  private func tick() {
    guard !backgrounded, let view = webView else { return }
    if health.timedOut(at: now) { recover(health.ready ? "heartbeat_timeout" : "startup_timeout"); return }
    guard health.ready, !pingPending else { return }
    pingPending = true
    view.evaluateJavaScript("globalThis.dataRuntime.ping()") { [weak self, weak view] value, error in
      guard let self, let view, self.webView === view else { return }
      self.pingPending = false
      if error == nil, value as? Bool == true { self.health.acknowledged(at: self.now); self.acknowledgements += 1 }
    }
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let view = webView, message.webView === view, message.frameInfo.isMainFrame,
          let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
    switch type {
    case "ready":
      guard !health.ready, let workspace else { return }
      health.acknowledged(at: now)
      publish("syncing", reason: "runtime_ready")
      view.callAsyncJavaScript("globalThis.dataRuntime.start(workspace)", arguments: ["workspace": workspace], in: nil, in: .page) { [weak self, weak view] result in
        guard let self, let view, self.webView === view else { return }
        if case .failure = result { self.recover("start_failed") }
        else {
          view.callAsyncJavaScript("globalThis.dataRuntime.restoreSessions(ids, current)", arguments: ["ids": self.retainedSessions, "current": self.sessionId as Any? ?? NSNull()], in: nil, in: .page, completionHandler: nil)
        }
      }
    #if DEBUG
    case "backgroundProbe":
      guard backgroundProbe else { return }
      probeUpdates += 1
      if UIApplication.shared.applicationState == .background { probeBackgroundUpdates += 1 }
      emit(status())
    #endif
    case "diagnostic":
      #if DEBUG
      NSLog("LodyRuntime stage=%@ stream=%@", body["stage"] as? String ?? "", body["stream"] as? String ?? "")
      #endif
    case "sessionSubscriptions":
      if let ids = body["ids"] as? [String] { retainedSessions = ids }
    case "session", "sessionCache":
      if #available(iOS 26.0, *), let work = body["backgroundWork"] as? [String: Any] {
        ContinuedSessionTasks.shared.update(work, owner: owner)
      }
      guard let id = body["sessionId"] as? String,
            let session = body["session"] as? String else { return }
      let fits = session.utf8.count <= 12 * 1024 * 1024
      if fits, body["synced"] as? Bool == true, let workspace, !userId.isEmpty {
        let generation = self.generation, userId = self.userId
        LocalStore.queue.async { [weak self] in
          guard let self else { return }
          do { try self.localStore.writeSession(session, userId: userId, workspace: workspace, id: id) }
          catch {
            DispatchQueue.main.async { [weak self] in
              guard let self, self.generation == generation, self.workspace != nil, !self.cacheErrorShown else { return }
              self.cacheErrorShown = true
              self.emit(self.status().merging(["reason": "session_cache_failed"], uniquingKeysWith: { _, new in new }))
            }
          }
        }
      }
      guard type == "session", id == sessionId else { return }
      let payload = fits ? session : #"{"v":1,"overflow":true}"#
      emit(status().merging(["sessionId": id, "session": payload], uniquingKeysWith: { _, new in new }))
    case "grant": fetchGrant(view: view)
    case "catalog":
      guard let catalog = body["catalog"] as? String, catalog.utf8.count <= 12 * 1024 * 1024 else { return }
      publish("live", reason: "catalog", extra: ["catalog": catalog, "revision": body["revision"] ?? 0])
    case "synced":
      if phase != "live" { publish("live", reason: "synced") }
    case "syncError": publish("offline", reason: body["reason"] as? String ?? "sync_failed")
    default: break
    }
  }
  func openSession(_ id: String) {
    if sessionId != id { attachmentTask?.cancel(); attachmentTask = nil }
    sessionId = id
    guard health.ready, let view = webView else { return }
    view.callAsyncJavaScript("return await globalThis.dataRuntime.session(id)", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
  }
  func closeSession(_ id: String) {
    ContentStore.shared.clear(session: id)
    guard sessionId == id else { return }
    attachmentTask?.cancel(); attachmentTask = nil
    sessionId = nil
    webView?.evaluateJavaScript("globalThis.dataRuntime.closeSession()", completionHandler: nil)
  }
  func sendTurn(_ payload: String, promise: Promise) {
    guard let data = payload.data(using: .utf8), data.count <= 128 * 1024,
          var args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let attachments = args.removeValue(forKey: "attachments") as? [[String: Any]], !attachments.isEmpty else {
      command("sendTurn", payload: payload, promise: promise); return
    }
    guard health.ready, let workspace, let sessionId, args["sessionId"] as? String == sessionId, attachmentTask == nil else {
      promise.resolve(#"{"state":"not_sent","reason":"会话尚未就绪，请稍后重试"}"#); return
    }
    if #available(iOS 26.0, *), !backgrounded {
      args["backgroundTaskId"] = ContinuedSessionTasks.shared.begin(owner: owner)
    }
    let backgroundTaskId = args["backgroundTaskId"] as? String
    let generation = self.generation
    attachmentTask = Task.detached { [weak self] in
      do {
        args["attachmentBlocks"] = try await SessionAttachments.upload(attachments, workspace: workspace, session: sessionId)
        try Task.checkCancellation()
        let prepared = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        await MainActor.run { [weak self] in
          guard let self, self.generation == generation, self.sessionId == sessionId, !Task.isCancelled else {
            if #available(iOS 26.0, *), let backgroundTaskId { ContinuedSessionTasks.shared.finish(backgroundTaskId, success: false) }
            promise.resolve(#"{"state":"not_sent","reason":"连接已切换，消息尚未发送"}"#); return
          }
          self.attachmentTask = nil
          self.command("sendTurn", payload: prepared, promise: promise)
        }
      } catch {
        let result = (try? JSONSerialization.data(withJSONObject: ["state": "not_sent", "reason": error.localizedDescription])) ?? Data()
        await MainActor.run { [weak self] in
          if let self, self.generation == generation, self.sessionId == sessionId, !Task.isCancelled { self.attachmentTask = nil }
          if #available(iOS 26.0, *), let backgroundTaskId { ContinuedSessionTasks.shared.finish(backgroundTaskId, success: false) }
          promise.resolve(String(data: result, encoding: .utf8)!)
        }
      }
    }
  }
  /// The command guard matches the payload's workspace, which a diagnostic has
  /// no way to know. Inject the runtime's own.
  func debugProbeSchema(promise: Promise) {
    guard let workspace, let payload = try? String(
      data: JSONSerialization.data(withJSONObject: ["workspaceId": workspace]),
      encoding: .utf8
    ) else {
      fail(promise, "not_ready", "尚未连接工作区")
      return
    }
    command("probeSchema", payload: payload, promise: promise)
  }

  /// Expo's `reject(code:description:)` drops the description in this version,
  /// so every failure reads "undefined reason". Carry the text in an NSError.
  // Bodies stay in ContentStore; RN only receives a handle plus metadata.
  private static func parkContent(method: String, session: String, json: String) -> String {
    guard let data = json.data(using: .utf8),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["status"] as? String == "ok" else { return json }
    let path = object["path"] as? String ?? ""
    if method == "readFile" {
      let binary = object["kind"] as? String == "binary"
      let mimeType = object["mimeType"] as? String
      let body: Data
      if binary {
        guard let decoded = Data(base64Encoded: object["base64"] as? String ?? "") else { return json }
        body = decoded
      } else {
        body = Data((object["text"] as? String ?? "").utf8)
      }
      let kind = ContentStore.classify(path: path, binary: binary, mimeType: mimeType)
      object["kind"] = kind
      object["text"] = nil; object["base64"] = nil
      object["handle"] = ContentStore.shared.put(StoredContent(data: body, kind: kind, path: path, session: session, mimeType: mimeType))
    } else {
      var sides: [String: String] = [:]
      for key in ["old", "new"] {
        let side = object[key] as? [String: Any]
        sides[key] = side?["text"] as? String
        object[key + "Kind"] = side?["kind"] as? String ?? "missing"
        object[key] = nil
      }
      let body = (try? JSONSerialization.data(withJSONObject: sides)) ?? Data()
      object["handle"] = ContentStore.shared.put(StoredContent(data: body, kind: "diff", path: path, session: session, mimeType: nil))
    }
    guard let output = try? JSONSerialization.data(withJSONObject: object), let text = String(data: output, encoding: .utf8) else { return json }
    return text
  }
  private func fail(_ promise: Promise, _ code: String, _ message: String) {
    promise.reject(
      NSError(
        domain: "LodyKit.DataRuntime",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "\(code): \(message)"]
      )
    )
  }

  private static let sessionCommands: Set<String> = ["sendTurn", "itemDetail", "respondPermission", "turnDiff", "fileDiff", "readFile"]
  private static let contentCommands: Set<String> = ["turnDiff", "fileDiff", "readFile"]
  func command(_ method: String, payload: String, promise: Promise) {
    guard health.ready, let view = webView, let data = payload.data(using: .utf8), data.count <= 128 * 1024,
          var args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (Self.sessionCommands.contains(method)
            ? args["sessionId"] as? String == sessionId
            : args["workspaceId"] as? String == workspace) else {
      if method == "sendTurn" {
        promise.resolve(#"{"state":"not_sent","reason":"会话尚未同步，请稍后重试"}"#)
      } else {
        fail(promise, "not_ready", "会话尚未同步")
      }
      return
    }
    let id = UUID(); commands[id] = promise
    if method == "sendTurn", args["backgroundTaskId"] == nil, #available(iOS 26.0, *), !backgrounded {
      args["backgroundTaskId"] = ContinuedSessionTasks.shared.begin(owner: owner)
    }
    let backgroundTaskId = args["backgroundTaskId"] as? String
    DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
      guard let self, let pending = self.commands.removeValue(forKey: id) else { return }
      if #available(iOS 26.0, *), let backgroundTaskId { ContinuedSessionTasks.shared.finish(backgroundTaskId, success: false) }
      self.fail(pending, "send_timeout", "发送结果未知，请查看同步记录，不要重复发送")
    }
    // A JS throw reaches Swift as a WKError with no usable message, so the
    // runtime reports failures as a value instead of an exception.
    let script = """
    try { return JSON.stringify(await globalThis.dataRuntime[method](args)) }
    catch (error) {
      const detail = {
        type: typeof error,
        name: error && error.name,
        message: error && error.message,
        stack: error && error.stack,
        text: String(error),
        keys: error && typeof error === "object" ? Object.getOwnPropertyNames(error) : [],
      }
      return JSON.stringify({ __commandError: JSON.stringify(detail) })
    }
    """
    view.callAsyncJavaScript(script, arguments: ["args": args, "method": method], in: nil, in: .page) { [weak self, weak view] result in
      guard let self, let view, self.webView === view, let pending = self.commands.removeValue(forKey: id) else { return }
      if #available(iOS 26.0, *), let backgroundTaskId {
        let value = try? result.get() as? String
        let data = value?.data(using: .utf8)
        let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if reply?["state"] as? String != "accepted" {
          ContinuedSessionTasks.shared.finish(backgroundTaskId, success: false)
        }
      }
      switch result {
      case .success(let value):
        if let text = value as? String, text.contains("__commandError"),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["__commandError"] as? String {
          fail(pending, "command_failed", message)
          return
        }
        if Self.contentCommands.contains(method), let text = value as? String {
          pending.resolve(Self.parkContent(method: method, session: args["sessionId"] as? String ?? "", json: text))
          return
        }
        pending.resolve(value)
      case .failure(let error):
        // WKWebView puts the JS exception text in userInfo; localizedDescription
        // alone reports "undefined reason" and hides every runtime failure.
        let info = (error as NSError).userInfo
        let detail = [
          info["WKJavaScriptExceptionMessage"] as? String,
          info[NSLocalizedDescriptionKey] as? String,
        ].compactMap { $0 }.first ?? error.localizedDescription
        fail(pending, "send_failed", detail)
      }
    }
  }
  private func fetchGrant(view: WKWebView) {
    guard grantTask == nil, let workspace else { return }
    do {
      guard let token = try AuthKeychain.read() else { throw NSError(domain: "MissingAuth", code: 1) }
      var request = URLRequest(url: URL(string: "https://backend.lody.ai/api/loro-streams/token")!, timeoutInterval: 15)
      request.httpMethod = "POST"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: ["workspaceId": workspace])
      grantTask = URLSession.shared.dataTask(with: request) { [weak self, weak view] data, response, error in
        DispatchQueue.main.async {
          guard let self, let view, self.webView === view else { return }
          self.grantTask = nil
          var grant: [String: Any]?
          if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
             let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let token = value["token"] as? String, !token.isEmpty,
             let address = value["gatewayBaseUrl"] as? String,
             let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
             let expiry = value["expiresIn"] as? Double, expiry > 0 {
            grant = ["token": token, "gatewayBaseUrl": address, "expiresIn": expiry]
          }
          self.deliverGrant(grant, view: view)
        }
      }
      grantTask?.resume()
    } catch { deliverGrant(nil, view: view) }
  }
  private func deliverGrant(_ grant: [String: Any]?, view: WKWebView) {
    view.callAsyncJavaScript("globalThis.dataRuntime.grant(value)", arguments: ["value": grant as Any? ?? NSNull()], in: nil, in: .page, completionHandler: nil)
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = navigationAction.request.url
    let bundledLoad = navigationAction.navigationType == .other && (url?.absoluteString == "about:blank" || url?.absoluteString == "https://lody.ai/")
    decisionHandler(bundledLoad ? .allow : .cancel)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if self.webView === webView { recover("process_terminated") } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView { recover("navigation_failed") } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView { recover("navigation_failed") } }
  #if DEBUG
  private var backgroundProbe = false
  private var probeUpdates = 0
  private var probeBackgroundUpdates = 0
  func debugBackground(_ action: String, promise: Promise) {
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify"), workspace == nil || backgroundProbe else {
      fail(promise, "probe_unavailable", "仅限独立离线验收"); return
    }
    switch action {
    case "start":
      backgroundProbe = true; probeUpdates = 0; probeBackgroundUpdates = 0
      start(workspace: "background-fixture", owner: "background-fixture", userId: "")
      sessionId = "background-fixture"
    case "send":
      command("sendTurn", payload: #"{"sessionId":"background-fixture"}"#, promise: promise)
      return
    case "complete": webView?.evaluateJavaScript("globalThis.dataRuntime.complete()", completionHandler: nil)
    case "expire":
      if #available(iOS 26.0, *) { ContinuedSessionTasks.shared.debugExpire() }
    case "stop": stop(); backgroundProbe = false
    default: break
    }
    promise.resolve("{}")
  }
  // Synthetic server boundary, exercising the production WebView owner and scheduler.
  private static let backgroundProbeHTML = #"""
  <script>
  const post = value => webkit.messageHandlers.dataRuntime.postMessage(value);
  let work;
  globalThis.dataRuntime = {
    ping: () => true,
    start() { post({type: 'synced'}); },
    restoreSessions() {},
    sendTurn(args) { work = args.backgroundTaskId; return {state: 'accepted', id: 'fixture-turn'}; },
    complete() {
      post({type: 'sessionCache', backgroundWork: {id: work, state: 'completed'}});
      work = undefined;
    }
  };
  setInterval(() => {
    if (work) post({type: 'sessionCache', backgroundWork: {id: work, state: 'receiving'}});
    post({type: 'backgroundProbe'});
  }, 1000);
  post({type: 'ready'});
  </script>
  """#
  func debugHang() { webView?.evaluateJavaScript("while (true) {}", completionHandler: nil) }
  func debugRestart() { recover("debug_process_loss") }
  #endif
  deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) }; timer?.invalidate() }
}
