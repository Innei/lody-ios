import LodyRuntime
import LodyCore
import ExpoModulesCore
import WebKit
import UIKit

// The owner lives in Swift, so a wedged JS event loop cannot disable its watchdog.
@MainActor
final class DataRuntime: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private var webView: WKWebView?
  private var sessionId: String?
  private var retainedSessions: [String] = []
  private var reservedSessions: [String] = []
  private var userId = ""
  private let localStore: LocalStore
  private let billing = WorkspaceBilling()
  private var cacheErrorShown = false
  private var commands: [UUID: CommandSink] = [:]
  private var timer: Timer?
  private let sendPreparation = SendPreparation()
  private var grantTask: URLSessionDataTask?
  private var githubTasks: [String: Task<Void, Never>] = [:]
  private var shareTasks: [String: Task<Void, Never>] = [:]
  private var health = RuntimeHealth()
  private var pingPending = false
  private var workspace: String?
  private var workspaceSlug = ""
  private var workspaceName = ""
  private var owner = ""
  private var generation = 0
  private var backgrounded = false
  private var phase = "stopped"
  private var reason = ""
  private var lastStartReason = ""
  private var acknowledgements = 0
  private let observers = NotificationObservers()
  private let emit: ([String: Any]) -> Void
  private let emitUploadProgress: ([String: Any]) -> Void
  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  init(localStore: LocalStore, emit: @escaping ([String: Any]) -> Void,
    emitUploadProgress: @escaping ([String: Any]) -> Void) {
    self.localStore = localStore
    self.emit = emit
    self.emitUploadProgress = emitUploadProgress
    super.init()
    observers.add(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.workspace != nil else { return }
        self.backgrounded = true
        self.health.suspend()
        self.publishPresenceUnknown()
        self.webView?.evaluateJavaScript("globalThis.dataRuntime?.setActive(false)", completionHandler: nil)
      }
    })
    observers.add(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { ContentStore.shared.clearAll() }
    })
    observers.add(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.workspace != nil, self.backgrounded else { return }
        self.backgrounded = false
        self.health.resume(at: self.now)
        self.pingPending = false
        if self.webView == nil { self.build(reason: "foreground") }
        else {
          self.webView?.evaluateJavaScript("globalThis.dataRuntime?.setActive(true)", completionHandler: nil)
          self.tick()
        }
      }
    })
  }
  func start(workspace: String, slug: String, name: String, owner: String, userId: String) {
    disposeView()
    if self.workspace != workspace || self.userId != userId {
      sessionId = nil; retainedSessions = []; reservedSessions = []; billing.clear()
    }
    self.userId = userId; cacheErrorShown = false
    self.workspace = workspace; self.owner = owner; health = RuntimeHealth()
    workspaceSlug = slug; workspaceName = name
    backgrounded = UIApplication.shared.applicationState == .background
    if backgrounded { publish("background", reason: "paused") }
    else { build(reason: "subscribe") }
  }
  func stop(owner: String? = nil) {
    if let owner, self.owner != owner { return }
    workspace = nil; sessionId = nil; retainedSessions = []; reservedSessions = []; userId = ""; billing.clear(); disposeView(); publish("stopped", reason: "unsubscribe")
  }
  func status() -> [String: any Sendable] {
    var value: [String: any Sendable] = ["owner": owner, "generation": generation, "state": phase, "reason": reason, "acknowledgements": acknowledgements, "lastStartReason": lastStartReason]
    if backgroundProbe {
      value["probeBackgroundUpdates"] = probeBackgroundUpdates
      value["probeUpdates"] = probeUpdates
      value["backgroundTaskState"] = SessionBackgroundTasks.shared.debugState
      value["backgroundTaskCount"] = SessionBackgroundTasks.shared.debugCount
    }
    return value
  }
  private func publish(_ state: String, reason: String, extra: [String: Any] = [:]) {
    self.phase = state; self.reason = reason
    emitStatus(extra)
  }
  private func emitStatus(_ extra: [String: Any] = [:]) {
    emit((status() as [String: Any]).merging(extra, uniquingKeysWith: { _, new in new }))
  }
  private func publishPresenceUnknown() {
    emitStatus(["machinePresence": #"{"state":"unknown","onlineMachineIds":[]}"#])
  }
  private func build(reason: String) {
    guard workspace != nil else { return }
    disposeView(); lastStartReason = reason; health.started(at: now); acknowledgements = 0
    let view = RuntimeDocument.makeWebView(handler: self, delegate: self)
    // A signature drift silently drops the optional policy witness, and with it the navigation guard.
    assert(responds(to: #selector(webView(_:decidePolicyFor:decisionHandler:) as (WKWebView, WKNavigationAction, @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) -> Void)))
    webView = view
    publish("starting", reason: reason)
    timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
      guard self != nil else { timer.invalidate(); return }
      MainActor.assumeIsolated { self?.tick() }
    }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    if backgroundProbe {
      view.loadHTMLString(Self.backgroundProbeHTML, baseURL: URL(string: "https://lody.ai"))
      return
    }
    do {
      try RuntimeDocument.load(in: view, bundle: Bundle(for: LodyKitModule.self))
    } catch { disposeView(); publish("failed", reason: "missing_resource") }
  }
  private func disposeView() {
    generation += 1
    sendPreparation.cancelAll(reason: "runtime_replaced")
    SessionBackgroundTasks.shared.finishAll(owner: owner)
    for promise in commands.values { fail(promise, "runtime_replaced", LodyStrings.text("native.runtime.replaced")) }; commands.removeAll()
    timer?.invalidate(); timer = nil
    grantTask?.cancel(); grantTask = nil
    githubTasks.values.forEach { $0.cancel() }; githubTasks.removeAll()
    shareTasks.values.forEach { $0.cancel() }; shareTasks.removeAll()
    pingPending = false
    let old = webView; webView = nil
    old?.evaluateJavaScript("globalThis.dataRuntime?.stop?.()", completionHandler: nil)
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
      view.callAsyncJavaScript("globalThis.dataRuntime.start(workspace, userId, active)", arguments: ["workspace": workspace, "userId": userId, "active": !backgrounded], in: nil, in: .page) { [weak self, weak view] result in
        guard let self, let view, self.webView === view else { return }
        if case .failure = result { self.recover("start_failed") }
        else {
          view.callAsyncJavaScript("globalThis.dataRuntime.restoreSessions(ids, current, reserved)", arguments: ["ids": self.retainedSessions, "current": self.sessionId as Any? ?? NSNull(), "reserved": self.reservedSessions], in: nil, in: .page, completionHandler: nil)
        }
      }
    case "backgroundProbe":
      guard backgroundProbe else { return }
      probeUpdates += 1
      if UIApplication.shared.applicationState == .background { probeBackgroundUpdates += 1 }
      emitStatus()
    case "diagnostic":
      #if DEBUG
      NSLog("LodyRuntime stage=%@ stream=%@", body["stage"] as? String ?? "", body["stream"] as? String ?? "")
      #endif
    case "sessionSubscriptions":
      if let ids = body["ids"] as? [String] { retainedSessions = ids }
      reservedSessions = body["reserved"] as? [String] ?? reservedSessions
    case "session", "sessionCache":
      if let work = body["backgroundWork"] as? [String: Any] {
        SessionBackgroundTasks.shared.update(work, owner: owner)
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
              self.emitStatus(["reason": "session_cache_failed"])
            }
          }
        }
      }
      guard type == "session", id == sessionId else { return }
      let payload = fits ? session : #"{"v":1,"overflow":true}"#
      emitStatus(["sessionId": id, "session": payload])
    case "shareProgress":
      if let progress = body["progress"] as? [String: Any] { emitStatus(["shareProgress": progress]) }
    case "shareRequest":
      guard let workspace, body["workspaceId"] as? String == workspace, body["userId"] as? String == userId,
        let id = body["id"] as? String, UUID(uuidString: id) != nil,
        let operation = body["operation"] as? String, let args = body["args"] as? [String: Any],
        shareTasks[id] == nil else { return }
      guard shareTasks.count < 4 else {
        view.callAsyncJavaScript("globalThis.dataRuntime.shareResult(id, null, true)", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
        return
      }
      let user = userId, generation = self.generation
      shareTasks[id] = Task { [weak self, weak view] in
        guard !Task.isCancelled, let self, let view, self.webView === view,
          self.generation == generation, self.workspace == workspace, self.userId == user else { return }
        let result: Any?
        switch operation {
        case "projectApi":
          result = try? await ProjectManagementCloud.run(args: args, workspace: workspace, userId: user)
        default:
          result = try? await SessionSharing.run(operation, args: args, workspace: workspace, userId: user)
        }
        guard !Task.isCancelled, self.webView === view,
          self.generation == generation, self.workspace == workspace, self.userId == user else { return }
        self.shareTasks.removeValue(forKey: id)
        view.callAsyncJavaScript("globalThis.dataRuntime.shareResult(id, value, failed)", arguments: ["id": id, "value": result ?? NSNull(), "failed": result == nil], in: nil, in: .page, completionHandler: nil)
      }
    case "githubMentions":
      guard let workspace, body["workspaceId"] as? String == workspace, body["userId"] as? String == userId,
            let id = body["id"] as? String, UUID(uuidString: id) != nil,
            let repo = body["repoFullName"] as? String, githubTasks[id] == nil else { return }
      guard githubTasks.count < 4 else {
        view.callAsyncJavaScript("globalThis.dataRuntime.githubMentionsResult(id, null)", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
        return
      }
      let user = userId, generation = self.generation
      githubTasks[id] = Task { [weak self, weak view] in
        guard !Task.isCancelled, let self, let view, self.webView === view,
          self.generation == generation, self.workspace == workspace, self.userId == user else { return }
        let result = try? await GitHubMentions.load(workspace: workspace, repo: repo)
        guard !Task.isCancelled, self.webView === view, self.generation == generation,
          self.workspace == workspace, self.userId == user else { return }
        self.githubTasks.removeValue(forKey: id)
        view.callAsyncJavaScript("globalThis.dataRuntime.githubMentionsResult(id, value)", arguments: ["id": id, "value": result as Any? ?? NSNull()], in: nil, in: .page, completionHandler: nil)
      }
    case "grant":
      guard body["workspaceId"] as? String == workspace, body["userId"] as? String == userId else { return }
      fetchGrant(view: view)
    case "machinePresence":
      guard !backgrounded, let presence = body["presence"] as? String, presence.utf8.count <= 1024 * 1024 else { return }
      publish(phase, reason: "machine_presence", extra: ["machinePresence": presence])
    case "catalog":
      guard let catalog = body["catalog"] as? String, catalog.utf8.count <= 12 * 1024 * 1024 else { return }
      publish("live", reason: "catalog", extra: ["catalog": catalog, "revision": body["revision"] ?? 0])
      LiveActivities.shared.sync(
        catalogJSON: catalog,
        workspaceId: workspace ?? "",
        workspaceSlug: workspaceSlug,
        workspaceName: workspaceName,
        userId: userId
      )
    case "synced":
      if phase != "live" { publish("live", reason: "synced") }
    case "syncError": publish("offline", reason: body["reason"] as? String ?? "sync_failed")
    default: break
    }
  }
  func openSession(_ id: String) {
    sessionId = id
    guard health.ready, let view = webView else { return }
    view.callAsyncJavaScript("return await globalThis.dataRuntime.session(id)", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
  }
  func closeSession(_ id: String) {
    ContentStore.shared.clear(session: id)
    guard sessionId == id else { return }
    sessionId = nil
    webView?.evaluateJavaScript("globalThis.dataRuntime.closeSession()", completionHandler: nil)
  }
  func ensureSession(_ id: String, promise: Promise) {
    guard let workspace, let payload = try? String(
      data: JSONSerialization.data(withJSONObject: ["sessionId": id, "workspaceId": workspace]),
      encoding: .utf8
    ) else {
      fail(promise, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return
    }
    command("ensureSession", payload: payload, promise: promise)
  }
  func releaseReserve(_ id: String) {
    reservedSessions.removeAll { $0 == id }
    guard health.ready, let view = webView else { return }
    view.callAsyncJavaScript(
      "return globalThis.dataRuntime.releaseReserve(args)",
      arguments: ["args": ["sessionId": id]],
      in: nil,
      in: .page,
      completionHandler: nil
    )
  }
  func createSession(_ payload: String, promise: Promise) {
    guard let workspace else { command("createSession", payload: payload, promise: promise); return }
    let user = userId, generation = self.generation
    Task { @MainActor in
      let entitlement = await billing.entitlement(workspace: workspace, user: user)
      guard self.generation == generation, self.workspace == workspace, self.userId == user else {
        promise.resolve(#"{"state":"rejected"}"#); return
      }
      command("createSession", payload: payload, promise: promise, billing: entitlement)
    }
  }
  func workspaceBillingEntitlement(workspace: String, user: String, promise: Promise) {
    guard self.workspace == workspace, userId == user else { promise.resolve("{}"); return }
    let generation = self.generation
    Task { @MainActor in
      let entitlement = await billing.entitlement(workspace: workspace, user: user)
      guard self.generation == generation, self.workspace == workspace, self.userId == user else {
        promise.resolve("{}"); return
      }
      let data = (try? JSONSerialization.data(withJSONObject: entitlement ?? [:])) ?? Data("{}".utf8)
      promise.resolve(String(data: data, encoding: .utf8) ?? "{}")
    }
  }
  func prepareSessionEdit(_ payload: String, promise: Promise) {
    let generation = self.generation
    guard let workspace, let session = sessionId else { promise.reject("not_ready", "Session unavailable"); return }
    Task { @MainActor in
      do {
        let result = try await command("editSession", payload: payload)
        guard var draft = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
              draft["state"] as? String == "ready" else { promise.resolve(result); return }
        var attachments: [[String: Any]] = []
        let originals = draft["attachments"] as? [[String: Any]] ?? []
        guard originals.count <= 16 else { throw SessionAttachments.error(LodyStrings.text("native.attachment.error.limit")) }
        let downloads = AttachmentDownloadBatch()
        // ponytail: download at most 16 originals for the shared local-file composer; use lazy remote previews if large attachments make editing slow.
        for block in originals {
          let image = block["type"] as? String == "image"
          guard let id = block[image ? "imageId" : "fileId"] as? String,
                let editID = block["editId"] as? String else { throw SessionAttachments.error("Invalid attachment") }
          let name = block["fileName"] as? String ?? (image ? "image.jpg" : "file")
          let directory = downloads.makeDirectory()
          let url = try await SessionAttachments.download(workspace: workspace,
            session: block["storageSessionId"] as? String ?? session, fileId: id, fileName: name,
            sizeBytes: block["sizeBytes"] as? Int, directory: directory, image: image)
          guard self.generation == generation, self.sessionId == session else { throw CancellationError() }
          attachments.append(["id": editID, "name": name, "uri": url.absoluteString, "kind": image ? "image" : "file"])
        }
        guard self.generation == generation, self.sessionId == session else { throw CancellationError() }
        draft["attachments"] = attachments
        let encoded = String(data: try JSONSerialization.data(withJSONObject: draft), encoding: .utf8)!
        downloads.handOff()
        promise.resolve(encoded)
      } catch { promise.reject("edit_prepare_failed", error.localizedDescription) }
    }
  }
  func sendTurn(_ payload: String, promise: Promise, method: String = "sendTurn") {
    guard health.ready, let view = webView, let workspace,
      let args = RuntimeCommandPayload.decode(payload, method: method),
      let target = args["sessionId"] as? String, !target.isEmpty,
      args["workspaceId"] == nil || args["workspaceId"] as? String == workspace,
      args["userId"] == nil || args["userId"] as? String == userId,
      method != "editSession" || sessionId == target else {
      promise.resolve(notSentJSON("native.runtime.sessionNotReady")); return
    }
    let user = userId, generation = self.generation
    let sendID = args["id"] as? String ?? ""
    var backgroundTaskId: String?
    guard let attempt = sendPreparation.begin(session: target, id: sendID, generation: generation, onCancel: { reason in
      if let backgroundTaskId { SessionBackgroundTasks.shared.finish(backgroundTaskId, success: false) }
      if reason == "send_cancelled" { promise.resolve(#"{"state":"not_sent","reason":"send_cancelled"}"#) }
      else { promise.resolve(notSentJSON("native.runtime.connectionSwitched")) }
    }) else { promise.resolve(notSentJSON("native.runtime.sessionNotReady")); return }
    let task = Task { @MainActor [weak self, weak view] in
      guard let self, let view else { return }
      @MainActor func owns() -> Bool {
        !Task.isCancelled && self.generation == generation && self.workspace == workspace
          && self.userId == user && self.webView === view
          && (method != "editSession" || self.sessionId == target)
          && self.sendPreparation.owns(session: target, token: attempt, generation: generation)
      }
      @MainActor func complete(_ result: String) {
        guard self.sendPreparation.finish(session: target, token: attempt, generation: generation) else { return }
        if let backgroundTaskId { SessionBackgroundTasks.shared.finish(backgroundTaskId, success: false) }
        promise.resolve(result)
      }
      do {
        let entitlement = await self.billing.entitlement(workspace: workspace, user: user)
        guard owns() else { complete(notSentJSON("native.runtime.connectionSwitched")); return }
        let attachments = args["attachments"] as? [[String: Any]] ?? []
        if !attachments.isEmpty {
          let result = try? await self.command("checkTurnQuota", payload: payload, billing: entitlement)
          guard owns() else { complete(notSentJSON("native.runtime.connectionSwitched")); return }
          if let result, let check = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
            check["state"] as? String == "not_sent" { complete(result); return }
        }
        var prepared = payload
        if !attachments.isEmpty {
          if !self.backgrounded {
            backgroundTaskId = SessionBackgroundTasks.shared.begin(owner: self.owner)
          }
          let uploadBackgroundTaskId = backgroundTaskId
          let upload = Task.detached { [weak self] in
            guard var uploadArgs = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let attachments = uploadArgs.removeValue(forKey: "attachments") as? [[String: Any]] else {
              throw SessionAttachments.error(LodyStrings.text("native.attachment.error.invalid"))
            }
            if let uploadBackgroundTaskId { uploadArgs["backgroundTaskId"] = uploadBackgroundTaskId }
            uploadArgs["attachmentBlocks"] = try await SessionAttachments.upload(attachments, workspace: workspace, session: target) { [weak self] attachmentID, phase, percent in
              DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.workspace == workspace, self.userId == user,
                  self.sendPreparation.owns(session: target, token: attempt, generation: generation) else { return }
                var event: [String: Any] = ["sessionId": target, "sendId": sendID,
                  "attachmentId": attachmentID, "phase": phase]
                if let percent { event["percent"] = percent }
                self.emitUploadProgress(event)
              }
            }
            try Task.checkCancellation()
            return String(data: try JSONSerialization.data(withJSONObject: uploadArgs), encoding: .utf8)!
          }
          prepared = try await withTaskCancellationHandler(operation: { try await upload.value }, onCancel: { upload.cancel() })
        }
        guard owns() else { complete(notSentJSON("native.runtime.connectionSwitched")); return }
        guard RuntimeCommandPayload.decode(prepared, method: method) != nil else { complete(notSentJSON("native.runtime.sessionNotReady")); return }
        guard self.sendPreparation.finish(session: target, token: attempt, generation: generation) else { return }
        self.command(method, payload: prepared, promise: promise, billing: entitlement)
      } catch {
        let result = (try? JSONSerialization.data(withJSONObject: ["state": "not_sent", "reason": error.localizedDescription])) ?? Data()
        complete(String(data: result, encoding: .utf8)!)
      }
    }
    sendPreparation.attach(task, session: target, token: attempt, generation: generation)
  }
  func cancelSessionSend(_ payload: String, promise: Promise) {
    guard payload.utf8.count <= 1024,
      let args = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
      let session = args["sessionId"] as? String, !session.isEmpty,
      let id = args["id"] as? String, !id.isEmpty else {
      fail(promise, "invalid_request", "Invalid send cancellation"); return
    }
    let matchesWorkspace = workspace != nil && (args["workspaceId"] == nil || args["workspaceId"] as? String == workspace)
    let cancelled = matchesWorkspace && sendPreparation.cancel(session: session, id: id, generation: generation, reason: "send_cancelled")
    let result = ["state": cancelled ? "cancelled" : "unknown", "id": id]
    promise.resolve(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
  }
  /// The command guard matches the payload's workspace, which a diagnostic has
  /// no way to know. Inject the runtime's own.
  func debugProbeSchema(promise: Promise) {
    guard let workspace, let payload = try? String(
      data: JSONSerialization.data(withJSONObject: ["workspaceId": workspace]),
      encoding: .utf8
    ) else {
      fail(promise, "not_ready", LodyStrings.text("native.runtime.notConnected"))
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
  private enum CommandSink {
    case promise(Promise)
    case continuation(CheckedContinuation<String, Error>)

    func resolve(_ value: Any?) {
      switch self {
      case .promise(let promise):
        promise.resolve(value)
      case .continuation(let continuation):
        if let text = value as? String {
          continuation.resume(returning: text)
        } else if value == nil {
          continuation.resume(returning: "")
        } else {
          continuation.resume(returning: String(describing: value as Any))
        }
      }
    }

    func reject(_ error: Error) {
      switch self {
      case .promise(let promise):
        promise.reject(error as NSError)
      case .continuation(let continuation):
        continuation.resume(throwing: error)
      }
    }
  }

  private func fail(_ promise: Promise, _ code: String, _ message: String) {
    fail(.promise(promise), code, message)
  }

  private func fail(_ sink: CommandSink, _ code: String, _ message: String) {
    sink.reject(
      NSError(
        domain: "LodyKit.DataRuntime",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "\(code): \(message)"]
      )
    )
  }

  private static let sessionCommands: Set<String> = ["editSession", "sendTurn", "controlTurn", "itemDetail", "respondPermission", "turnDiff", "fileDiff", "workspaceChanges", "readFile", "sessionPreview"]
  private static let contentCommands: Set<String> = ["turnDiff", "fileDiff", "readFile"]
  func command(_ method: String, payload: String, billing: [String: Any]? = nil) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      command(method, payload: payload, sink: .continuation(continuation), billing: billing)
    }
  }
  func command(_ method: String, payload: String, promise: Promise, billing: [String: Any]? = nil) {
    command(method, payload: payload, sink: .promise(promise), billing: billing)
  }
  private func command(_ method: String, payload: String, sink: CommandSink, billing: [String: Any]? = nil) {
    guard health.ready, let view = webView,
          var args = RuntimeCommandPayload.decode(payload, method: method) else {
      if method == "sendTurn" || method == "checkTurnQuota" {
        sink.resolve(notSentJSON("native.runtime.sessionNotSyncedRetry"))
      } else {
        fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      }
      return
    }
    let sessionKey = args["sessionId"] as? String
    let allowed: Bool
    if ["sendTurn", "checkTurnQuota", "ensureSession", "releaseReserve", "queueMessage", "checkSend"].contains(method) {
      allowed = workspace != nil && sessionKey?.isEmpty == false
        && (args["workspaceId"] == nil || args["workspaceId"] as? String == workspace)
    } else if Self.sessionCommands.contains(method) {
      allowed = sessionKey == sessionId
    } else {
      allowed = args["workspaceId"] as? String == workspace
    }
    let matchesScope = (args["userId"] == nil || args["userId"] as? String == userId)
      && (args["workspaceId"] == nil || args["workspaceId"] as? String == workspace)
    guard allowed && matchesScope else {
      if method == "sendTurn" || method == "checkTurnQuota" {
        sink.resolve(notSentJSON("native.runtime.sessionNotSyncedRetry"))
      } else {
        fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      }
      return
    }
    if method == "createSession" || method == "sendTurn" || method == "editSession" || method == "checkTurnQuota" {
      args["billingEntitlement"] = billing ?? NSNull()
    }
    if ["createSession", "sendTurn", "editSession", "checkTurnQuota", "queueMessage", "checkSend"].contains(method) {
      args["workspaceId"] = workspace
      args["userId"] = userId
    }
    if method == "remoteSettings" || method == "localProjects" || method == "mentionCatalog" { args["userId"] = userId }
    if ["projectCommand", "providerCommand", "runOptions"].contains(method) { args["userId"] = userId }
    if method == "editSession" || method == "sessionPreview" || method == "iosSimulatorControl" { args["userId"] = userId }
    let id = UUID(); commands[id] = sink
    if (method == "sendTurn" || (method == "editSession" && args["action"] as? String == "send")), args["backgroundTaskId"] == nil, !backgrounded {
      args["backgroundTaskId"] = SessionBackgroundTasks.shared.begin(owner: owner)
    }
    let backgroundTaskId = args["backgroundTaskId"] as? String
    var timeout: Double = 45
    if ["providerCommand", "runOptions", "queueMessage", "checkSend"].contains(method) { timeout = 90 }
    // Owned expansion/management reads expire at 120 seconds before any durable send.
    if ["createSession", "sendTurn", "editSession", "sessionSharing", "projectCommand"].contains(method) { timeout = 130 }
    if method == "sessionPreview" { timeout = 330 }
    if method == "iosSimulatorControl" { timeout = 100 }
    if method == "localProjects" && args["action"] as? String == "history" { timeout = 130 }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self, let pending = self.commands.removeValue(forKey: id) else { return }
      if let backgroundTaskId { SessionBackgroundTasks.shared.finish(backgroundTaskId, success: false) }
      self.fail(pending, "send_timeout", LodyStrings.text("native.runtime.sendTimeout"))
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
      if let backgroundTaskId {
        let value = try? result.get() as? String
        let data = value?.data(using: .utf8)
        let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if reply?["state"] as? String != "accepted" && reply?["awaitingGuide"] as? Bool != true {
          SessionBackgroundTasks.shared.finish(backgroundTaskId, success: reply?["state"] as? String == "queued")
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
    let user = userId, generation = self.generation
    do {
      guard let token = try AuthKeychain.read() else { throw NSError(domain: "MissingAuth", code: 1) }
      var request = URLRequest(url: URL(string: "https://backend.lody.ai/api/loro-streams/token")!, timeoutInterval: 15)
      request.httpMethod = "POST"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: ["workspaceId": workspace])
      grantTask = URLSession.shared.dataTask(with: request) { [weak self, weak view] data, response, error in
        DispatchQueue.main.async {
          guard let self, let view, self.webView === view, self.generation == generation,
            self.workspace == workspace, self.userId == user else { return }
          self.grantTask = nil
          var grant: [String: Any]?
          if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
             let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let token = value["token"] as? String, !token.isEmpty,
             let address = value["gatewayBaseUrl"] as? String,
             let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
             let expiry = value["expiresIn"] as? Double, expiry > 0 {
            grant = ["token": token, "gatewayBaseUrl": address, "expiresIn": expiry]
            if let suffix = value["shardHostSuffix"] as? String { grant?["shardHostSuffix"] = suffix }
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
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
    decisionHandler(RuntimeDocument.allows(navigationAction) ? .allow : .cancel)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if self.webView === webView { recover("process_terminated") } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView { recover("navigation_failed") } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView { recover("navigation_failed") } }
  private var backgroundProbe = false
  private var probeUpdates = 0
  private var probeBackgroundUpdates = 0
  func debugBackground(_ action: String, promise: Promise) {
    guard LodyUIVerify.enabled, workspace == nil || backgroundProbe else {
      fail(promise, "probe_unavailable", "offline acceptance builds only"); return
    }
    switch action {
    case "start":
      backgroundProbe = true; probeUpdates = 0; probeBackgroundUpdates = 0
      start(workspace: "background-fixture", slug: "background-fixture", name: "Background", owner: "background-fixture", userId: "")
      sessionId = "background-fixture"
    case "send":
      command("sendTurn", payload: #"{"sessionId":"background-fixture"}"#, promise: promise)
      return
    case "complete": webView?.evaluateJavaScript("globalThis.dataRuntime.complete()", completionHandler: nil)
    case "expire":
      SessionBackgroundTasks.shared.debugExpire()
    case "stop": stop(); backgroundProbe = false
    default: break
    }
    promise.resolve("{}")
  }
  // Synthetic server boundary, exercising the production WebView owner and background allowance.
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
}

final class NotificationObservers {
  private var tokens: [NSObjectProtocol] = []
  func add(_ token: NSObjectProtocol) { tokens.append(token) }
  deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

private func notSentJSON(_ key: String) -> String {
  let payload: [String: Any] = ["state": "not_sent", "reason": LodyStrings.text(key)]
  guard let data = try? JSONSerialization.data(withJSONObject: payload),
        let json = String(data: data, encoding: .utf8) else { return #"{"state":"not_sent"}"# }
  return json
}
