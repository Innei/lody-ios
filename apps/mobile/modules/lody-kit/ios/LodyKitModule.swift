import LodyCore
import ExpoModulesCore
import UIKit
import SafariServices

@Record
struct LodyRuntimeInfo {
  var moduleName: String = "LodyKit"
  var offlineProbe: Bool = false
  var uiVerifyHome: Bool = false
  var uiVerifySessionSearch: Bool = false
  var systemVersion: String = ""
}

@ExpoModule("LodyKit")
public final class LodyKitModule: Module, @unchecked Sendable {
  private let localStore = LocalStore.shared
  private let preferenceObservers = NotificationObservers()
  private let authObservers = NotificationObservers()
  private let catalogObservers = NotificationObservers()

  private static func previewURL(_ address: String) -> URL? {
    guard let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
          url.host?.hasSuffix(".trycloudflare.com") == true else { return nil }
    return url
  }
  @MainActor private lazy var accentPicker = AccentColorPicker()
  @MainActor private lazy var workspaceIconPicker = WorkspaceIconPicker()

  @MainActor private lazy var dataRuntime = DataRuntime(localStore: localStore,
    emit: { [weak self] event in self?.sendEvent("onDataRuntime", event) },
    emitUploadProgress: { [weak self] event in self?.sendEvent("onAttachmentUploadProgress", event) })

  @Event("onAppActive")
  var onAppActive: () -> Void

  @JS
  var initialInboxView: Int {
    let value = UserDefaults.standard.integer(forKey: "inboxView")
    return (0...2).contains(value) ? value : 0
  }

  @JS
  var initialInboxProjectSort: Int {
    let value = UserDefaults.standard.integer(forKey: "inboxProjectSort")
    return (0...2).contains(value) ? value : 0
  }

  @JS
  func saveAccentColor(value: String) { LodyAccentChoice.save(value) }

  @JS
  func accentHex(value: String, dark: Bool) -> String { LodyAccentChoice.hex(value, dark: dark) }

  @JS
  func accentForegroundHex(value: String) -> String {
    LodyAccentChoice.hex((LodyAccentChoice(rawValue: value) ?? .blue).foregroundColor)
  }

  @JS
  var initialLocale: String { Bundle.main.preferredLocalizations.first ?? "en" }

  @JS
  func readPreferences() -> String { LodyPreferences.json }

  @JS
  func resetQuickReplies() { LodyPreferences.resetQuickReplies() }

  @JS
  func readAuthState() -> String { AuthSession.published.json }

  @JS
  func localStoreGeneration() -> Int { localStore.generation }

  @JS
  func readCatalogState() -> String { CatalogSession.published.json }

  @JS
  func readCatalog() -> String { CatalogSession.published.raw }

  @JS
  func readOutbox(userId: String, workspaceId: String) -> String { OutboxSession.read(user: userId, workspace: workspaceId) }

  @JS
  func outboxInflight(sessionId: String) -> Bool { OutboxSession.published.inflight.contains(sessionId) }

  @JS
  func setOutboxInflight(sessionId: String, active: Bool) { OutboxSession.published.inflight.set(sessionId, active) }

  @JS
  var runtimeInfo: LodyRuntimeInfo {
    let offlineProbe = LodyUIVerify.offline
    let uiVerifyHome = LodyUIVerify.home
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let components = [version.majorVersion, version.minorVersion, version.patchVersion]
    return LodyRuntimeInfo(
      moduleName: "LodyKit",
      offlineProbe: offlineProbe,
      uiVerifyHome: uiVerifyHome,
      uiVerifySessionSearch: LodyUIVerify.enabled && LodyUIVerify.has("--ui-verify-search"),
      systemVersion: components.prefix(version.patchVersion == 0 ? 2 : 3).map(String.init).joined(separator: ".")
    )
  }

  public override func didCreate() {
    Task { @MainActor in
      lodyApplyWindowAccent()
      LiveActivities.shared.syncAppIcon()
      PushNotifications.shared.onClickAvailable = { [weak self] in self?.sendEvent("onPushClick", [:]) }
    }
    Task { @MainActor [weak self] in
      let auth = AuthSession.shared
      auth.presenter = { self?.appContext?.utilities?.currentViewController() }
      auth.stopRuntime = { self?.dataRuntime.stop() }
      let outbox = OutboxSession.shared
      outbox.presenter = { self?.appContext?.utilities?.currentViewController() }
      outbox.emit = { key in self?.sendEvent("onOutboxChange", ["key": key]) }
      LodyShell.shared.emit = { type, id in self?.sendEvent("onNav", ["type": type, "id": id]) }
      LodyShell.shared.emitOpen = { page, params, options, container in
        self?.sendEvent("onNav", ["type": "open", "page": page, "params": params, "options": options, "container": container])
      }
      if let runtime = self?.dataRuntime {
        DataRuntime.current = runtime
        outbox.attach(runtime)
        CatalogSession.shared.attach(runtime)
      }
      auth.start()
    }
    authObservers.add(NotificationCenter.default.addObserver(forName: .lodyAuthDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.sendEvent("onAuthChange", ["json": AuthSession.published.json])
    })
    catalogObservers.add(NotificationCenter.default.addObserver(forName: .lodyCatalogDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.sendEvent("onCatalogChange", ["json": CatalogSession.published.json])
    })
    for name in [Notification.Name.lodyAppearanceDidChange, .lodyPreferencesDidChange] {
      preferenceObservers.add(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.sendEvent("onPreferencesChange", ["json": LodyPreferences.json])
      })
    }
    ContentPreview.clearAll()
    if LodyUIVerify.offline {
      URLProtocol.registerClass(OfflineProbe.self)
    }
  }

  public override func willDestroy() {
    Task { @MainActor in
      self.dataRuntime.stop()
      self.accentPicker.dismiss()
      PushNotifications.shared.onClickAvailable = nil
    }
  }

  @JS
  func setSettingsPreview(json: String) {
    Task { @MainActor in SettingsPreview.set(json) }
  }

  @JS
  func showToast(message: String, kind: String) {
    Task { @MainActor in LodyToastOverlay.shared.show(message: message, kind: kind) }
  }

  @JS
  func prepareSheetZoom(sourceLabel: String) {
    // Must be armed before the shell's presentation lands on the main queue,
    // so this blocks JS until the main thread has run it.
    if Thread.isMainThread {
      MainActor.assumeIsolated { LodySheetZoom.prepare(sourceLabel: sourceLabel) }
      return
    }
    DispatchQueue.main.sync {
      MainActor.assumeIsolated { LodySheetZoom.prepare(sourceLabel: sourceLabel) }
    }
  }

  @JS
  func copyText(text: String) {
    if Thread.isMainThread {
      UIPasteboard.general.string = text
      return
    }
    DispatchQueue.main.sync { UIPasteboard.general.string = text }
  }

  @JS
  func showSessionBanner(title: String, kind: String) {
    Task { @MainActor in LodyToastOverlay.shared.showBanner(title: title, kind: kind) }
  }

  @JS
  func dismissSessionBanner() {
    Task { @MainActor in LodyToastOverlay.shared.dismissBanner() }
  }

  @JS
  func saveInboxView(index: Int) {
    UserDefaults.standard.set((0...2).contains(index) ? index : 0, forKey: "inboxView")
  }

  @JS
  func saveInboxProjectSort(index: Int) {
    UserDefaults.standard.set((0...2).contains(index) ? index : 0, forKey: "inboxProjectSort")
  }

  @JS
  func saveDarkBackground(value: String) {
    LodyDarkBackground.save(value)
  }

  @JS
  func readInboxExpansion() -> [String: Bool] {
    UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
  }

  @JS
  func saveInboxExpansion(projectID: String, expanded: Bool) {
    var values = UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
    values[projectID] = expanded
    UserDefaults.standard.set(values, forKey: "inboxExpansion")
  }

  private func pinOrderKey(userId: String, workspaceId: String) -> String {
    "inboxPinOrder.\(userId).\(workspaceId)"
  }

  @JS
  func readInboxPinOrder(userId: String, workspaceId: String) -> [String] {
    guard !userId.isEmpty, !workspaceId.isEmpty else { return [] }
    return UserDefaults.standard.stringArray(forKey: pinOrderKey(userId: userId, workspaceId: workspaceId)) ?? []
  }

  @JS
  func saveInboxPinOrder(userId: String, workspaceId: String, ids: [String]) {
    guard !userId.isEmpty, !workspaceId.isEmpty else { return }
    UserDefaults.standard.set(ids, forKey: pinOrderKey(userId: userId, workspaceId: workspaceId))
  }

  @MainActor private static func settle(_ task: Task<Void, Error>, _ promise: Promise) {
    Task { @MainActor in
      switch await task.result {
      case .success: promise.resolve(nil)
      case .failure(let error):
        let code = error as? OutboxError == .scopeExpired ? "pending_send_scope_expired" : "pending_send_write_failed"
        promise.reject(NSError(domain: "LodyKit.Outbox", code: 1, userInfo: [NSLocalizedDescriptionKey: code]))
      }
    }
  }

  public func definition() -> ModuleDefinition {
    AsyncFunction("sessionSharing") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated { self.dataRuntime.sessionSharing(payload, promise: promise) }
    }.runOnQueue(.main)
    Events("onDataRuntime", "onPushClick", "onAttachmentUploadProgress", "onPreferencesChange", "onAuthChange", "onCatalogChange", "onOutboxChange", "onNav")
    AsyncFunction("outboxPut") { (userId: String, workspaceId: String, json: String, promise: Promise) in
      MainActor.assumeIsolated { Self.settle(OutboxSession.shared.put(user: userId, workspace: workspaceId, json: json), promise) }
    }.runOnQueue(.main)
    AsyncFunction("outboxRemove") { (userId: String, workspaceId: String, sessionId: String, promise: Promise) in
      MainActor.assumeIsolated { Self.settle(OutboxSession.shared.remove(user: userId, workspace: workspaceId, sessionId: sessionId), promise) }
    }.runOnQueue(.main)
    AsyncFunction("navPresent") { (json: String) in
      MainActor.assumeIsolated { LodyShell.shared.present(json) }
    }.runOnQueue(.main)
    AsyncFunction("navClose") { (id: Int) in
      MainActor.assumeIsolated { LodyShell.shared.close(id) }
    }.runOnQueue(.main)
    AsyncFunction("navPopToRoot") {
      MainActor.assumeIsolated { LodyShell.shared.popToRoot() }
    }.runOnQueue(.main)
    AsyncFunction("navSetStack") { (ids: [Int]) in
      MainActor.assumeIsolated { LodyShell.shared.setStack(ids) }
    }.runOnQueue(.main)
    AsyncFunction("setForegroundSession") { (sessionId: String) in
      MainActor.assumeIsolated { OutboxSession.shared.setForeground(sessionId) }
    }.runOnQueue(.main)
    AsyncFunction("debugOutboxFixture") { (action: String) -> String in
      MainActor.assumeIsolated { OutboxSession.shared.debugFixture(action) }
    }.runOnQueue(.main)
    AsyncFunction("selectWorkspace") { (workspaceId: String) in
      MainActor.assumeIsolated { CatalogSession.shared.selectWorkspace(workspaceId) }
    }.runOnQueue(.main)
    AsyncFunction("refreshCatalog") {
      MainActor.assumeIsolated { CatalogSession.shared.refresh() }
    }.runOnQueue(.main)
    AsyncFunction("watchSession") { (id: String) in
      MainActor.assumeIsolated { self.dataRuntime.openSession(id) }
    }.runOnQueue(.main)
    AsyncFunction("unwatchSession") { (id: String) in
      MainActor.assumeIsolated { self.dataRuntime.closeSession(id) }
    }.runOnQueue(.main)
    AsyncFunction("ensureSession") { (id: String, promise: Promise) in
      MainActor.assumeIsolated { self.dataRuntime.ensureSession(id, sink: .promise(promise)) }
    }.runOnQueue(.main)
    AsyncFunction("releaseReserve") { (id: String) in
      MainActor.assumeIsolated { self.dataRuntime.releaseReserve(id) }
    }.runOnQueue(.main)
    AsyncFunction("readContentText") { (handle: String) -> String? in
      MainActor.assumeIsolated {
        ContentStore.shared.get(handle).flatMap { String(data: $0.data, encoding: .utf8) }
      }
    }.runOnQueue(.main)
    AsyncFunction("previewContent") { (handle: String) in
      try MainActor.assumeIsolated {
        guard let controller = self.appContext?.utilities?.currentViewController() else {
          throw NSError(domain: "LodyKit.ContentPreview", code: 2)
        }
        try ContentPreview.present(handle: handle, from: controller)
      }
    }.runOnQueue(.main)
    AsyncFunction("debugHangDataRuntime") {
      MainActor.assumeIsolated { self.dataRuntime.debugHang() }
    }.runOnQueue(.main)
    AsyncFunction("debugRestartDataRuntime") {
      MainActor.assumeIsolated { self.dataRuntime.debugRestart() }
    }.runOnQueue(.main)
    AsyncFunction("readLocalValue") { (key: String) in try self.localStore.read(key) }.runOnQueue(LocalStore.queue)
    AsyncFunction("searchInbox") { (userId: String, workspaceId: String, query: String) in
      try self.localStore.searchInbox(userID: userId, workspaceID: workspaceId, query: query)
    }.runOnQueue(LocalStore.queue)
    AsyncFunction("writeLocalValue") { (key: String, value: String, generation: Int?) in
      try self.localStore.write(key, value, generation: generation)
    }.runOnQueue(LocalStore.queue)
    AsyncFunction("restoreAuth") { (promise: Promise) in
      Task { @MainActor in
        await AuthSession.shared.restore()
        promise.resolve(nil)
      }
    }
    AsyncFunction("login") { (promise: Promise) in
      Task { @MainActor in
        do { try await AuthSession.shared.login(); promise.resolve(nil) }
        catch { promise.reject("ERR_AUTH", error.localizedDescription) }
      }
    }
    AsyncFunction("cancelLogin") {
      MainActor.assumeIsolated { AuthSession.shared.cancel() }
    }.runOnQueue(.main)
    AsyncFunction("logout") { (promise: Promise) in
      Task { @MainActor in
        await AuthSession.shared.logout()
        promise.resolve(nil)
      }
    }
    AsyncFunction("reopenAuthBrowser") {
      MainActor.assumeIsolated { AuthSession.shared.reopen() }
    }.runOnQueue(.main)
    AsyncFunction("updateWorkspace") { (workspaceId: String, name: String, promise: Promise) in
      Task { @MainActor in
        do { try await AuthSession.shared.updateWorkspace(id: workspaceId, name: name); promise.resolve(nil) }
        catch { promise.reject("ERR_WORKSPACE", error.localizedDescription) }
      }
    }
    AsyncFunction("updateWorkspaceIcon") { (workspaceId: String, uri: String, name: String, type: String, size: Int, promise: Promise) in
      Task { @MainActor in
        do {
          guard let url = URL(string: uri) else { throw AuthFailure.text("workspace.edit.iconUploadFailed") }
          let file = WorkspaceIconFile(url: url, name: name, type: type, size: size)
          promise.resolve(try await AuthSession.shared.updateWorkspaceIcon(id: workspaceId, file: file))
        } catch { promise.reject("ERR_WORKSPACE", error.localizedDescription) }
      }
    }
    AsyncFunction("sessionPreview") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated { self.dataRuntime.sessionPreview(payload, promise: promise) }
    }.runOnQueue(.main)
    AsyncFunction("iosSimulatorControl") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated { self.dataRuntime.iosSimulatorControl(payload, promise: promise) }
    }.runOnQueue(.main)
    AsyncFunction("openPreviewBrowser") { (address: String) in
      try MainActor.assumeIsolated {
        guard let url = Self.previewURL(address),
              let controller = self.appContext?.utilities?.currentViewController() else {
          throw NSError(domain: "LodyKit.PreviewBrowser", code: 1)
        }
        controller.present(SFSafariViewController(url: url), animated: true)
      }
    }.runOnQueue(.main)
    AsyncFunction("showAccentColorPicker") { (title: String, promise: Promise) in
      MainActor.assumeIsolated {
        guard let controller = self.appContext?.utilities?.currentViewController() else {
          promise.reject("ERR_COLOR_PICKER", "No presenting controller")
          return
        }
        self.accentPicker.present(from: controller, title: title)
        promise.resolve(nil)
      }
    }.runOnQueue(.main)
    AsyncFunction("getAppIcon") { MainActor.assumeIsolated { LodyAppIcon.current } }.runOnQueue(.main)
    AsyncFunction("setAppIcon") { (name: String, promise: Promise) in
      MainActor.assumeIsolated {
        LodyAppIcon.set(name) { result in
          switch result {
          case .success(let value): promise.resolve(value)
          case .failure(let error): promise.reject("ERR_APP_ICON", "\(error)")
          }
        }
      }
    }.runOnQueue(.main)
    AsyncFunction("selectionFeedback") {
      UISelectionFeedbackGenerator().selectionChanged()
    }.runOnQueue(.main)
    AsyncFunction("debugReplyHaptics") { (chunksMs: [Double], values: [String: Double]) -> Int in
      MainActor.assumeIsolated {
        var config = ChatReplyPulses.Config()
        let seconds = { (key: String) in values[key].map { $0 / 1000 } }
        config.window = seconds("window") ?? config.window
        config.duration = seconds("duration") ?? config.duration
        config.interval = seconds("interval") ?? config.interval
        config.count = values["count"].map { Int($0) } ?? config.count
        config.intensity = values["intensity"].map { Float($0) } ?? config.intensity
        config.endIntensity = values["endIntensity"].map { Float($0) } ?? config.endIntensity
        config.curve = values["curve"].map { Float($0) } ?? config.curve
        config.sharpness = values["sharpness"].map { Float($0) } ?? config.sharpness
        let pulses = ChatReplyPulses.schedule(chunks: chunksMs.filter(\.isFinite).map { $0 / 1000 }, config: config)
        ChatReplyHaptics.preview.play(pulses, sharpness: config.sharpness)
        return pulses.count
      }
    }.runOnQueue(.main)
    AsyncFunction("dismissSheetZoom") { (promise: Promise) in
      MainActor.assumeIsolated { LodySheetZoom.dismiss { promise.resolve() } }
    }.runOnQueue(.main)
    AsyncFunction("cancelComposerRelay") { (id: String) in
      LodyComposerView.cancelRelay(id)
    }.runOnQueue(.main)
    AsyncFunction("verifyPushSubscription") {
      #if DEBUG
      MainActor.assumeIsolated {
        guard let controller = self.appContext?.utilities?.currentViewController() else { return }
        PushNotifications.shared.onRegistered = { [weak controller] in
          if let controller { PushNotifications.shared.verify(from: controller) }
        }
        PushNotifications.shared.verify(from: controller)
      }
      #endif
    }.runOnQueue(.main)
    AsyncFunction("setPushUser") { (userId: String?) in MainActor.assumeIsolated { PushNotifications.shared.identify(userId) } }.runOnQueue(.main)
    AsyncFunction("pushStatus") { (promise: Promise) in MainActor.assumeIsolated { PushNotifications.shared.status { promise.resolve($0) } } }.runOnQueue(.main)
    AsyncFunction("requestPushPermission") { (promise: Promise) in MainActor.assumeIsolated { PushNotifications.shared.request { promise.resolve($0) } } }.runOnQueue(.main)
    AsyncFunction("pendingPushClick") { MainActor.assumeIsolated { PushNotifications.shared.readPending() } }.runOnQueue(.main)
    AsyncFunction("acknowledgePushClick") { (id: String) in MainActor.assumeIsolated { PushNotifications.shared.acknowledge(id) } }.runOnQueue(.main)
    AsyncFunction("liveActivityStatus") { MainActor.assumeIsolated { LiveActivities.shared.status() } }.runOnQueue(.main)
    AsyncFunction("setLiveActivitiesEnabled") { (enabled: Bool) in MainActor.assumeIsolated { LiveActivities.shared.enabled = enabled } }.runOnQueue(.main)
    AsyncFunction("debugLiveActivity") { (action: String) in
      MainActor.assumeIsolated { LiveActivities.shared.debug(action) }
    }.runOnQueue(.main)
    AsyncFunction("setPushVisibleRoute") { (route: String) in MainActor.assumeIsolated { PushNotifications.shared.visibleRoute = route } }.runOnQueue(.main)

    AsyncFunction("recordPushNavigation") { (id: String, source: String, outcome: String, reason: String) in
      DiagnosticsStore.shared.navigation(id: id, source: source, outcome: outcome, reason: reason)
    }
    AsyncFunction("githubPullRequest") { (payload: String) async throws -> String in
      try await GitHubPullRequests.run(payload)
    }
    AsyncFunction("pickWorkspaceIcon") { (promise: Promise) in
      MainActor.assumeIsolated {
        guard let controller = self.appContext?.utilities?.currentViewController() else {
          promise.reject("PICKER_UNAVAILABLE", "The workspace icon picker could not be presented")
          return
        }
        self.workspaceIconPicker.present(from: controller, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("githubRepositories") { (workspace: String, promise: Promise) in
      Task { @MainActor in
        if workspace == "ui-home", LodyUIVerify.mentions {
          promise.resolve(["LodyAI/FreshProject"]); return
        }
        if LodyUIVerify.enabled, workspace == "ui-project-picker" {
          promise.resolve((1...20).map { "Owner/Repo\($0)" }); return
        }
        do { promise.resolve(try await GitHubCloud.repositories(workspace: workspace)) }
        catch { promise.reject(error) }
      }
    }
    AsyncFunction("sessionCreationOptions") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated {
        if let response = MentionFixture.response(payload, options: true) { promise.resolve(response); return }
        self.dataRuntime.creationOptions(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("localProjects") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.localProjects(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("workspaceSettings") { (payload: String) async throws -> String in
      try await WorkspaceSettingsCloud.run(payload)
    }
    AsyncFunction("remoteSettings") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.remoteSettings(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("memorySettings") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.memorySettings(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("publishedShares") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.publishedShares(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("createSession") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.createSession(payload, sink: .promise(promise)) } }.runOnQueue(.main)
    AsyncFunction("workspaceBillingEntitlement") { (workspace: String, user: String, promise: Promise) in
      MainActor.assumeIsolated { self.dataRuntime.workspaceBillingEntitlement(workspace: workspace, user: user, promise: promise) }
    }.runOnQueue(.main)
    AsyncFunction("archiveSession") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.workspaceWrite(RuntimeContract.Calls.ArchiveSession.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("deleteSession") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated {
        guard OutboxSession.shared.allowsDeletion(payload) else {
          promise.reject(NSError(domain: "LodyKit.Outbox", code: 1, userInfo: [NSLocalizedDescriptionKey: "session_has_pending_send"]))
          return
        }
        self.dataRuntime.workspaceWrite(RuntimeContract.Calls.DeleteSession.self, payload: payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("pinSession") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.workspaceWrite(RuntimeContract.Calls.PinSession.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("markSessionRead") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.workspaceWrite(RuntimeContract.Calls.MarkSessionRead.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("renameSession") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.workspaceWrite(RuntimeContract.Calls.RenameSession.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("controlSessionTurn") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.sessionWrite(RuntimeContract.Calls.ControlTurn.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("sendSessionTurn") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.sendTurn(payload, sink: .promise(promise)) } }.runOnQueue(.main)
    AsyncFunction("readSessionEdit") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.readSessionEdit(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("prepareSessionEdit") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.prepareSessionEdit(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("sendSessionEdit") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.sendTurn(payload, sink: .promise(promise), edit: true) } }.runOnQueue(.main)
    AsyncFunction("sessionItemDetail") { (payload: String, promise: Promise) in
      try MainActor.assumeIsolated {
        if LodyUIVerify.enabled,
          let data = payload.data(using: .utf8),
          let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          params["sessionId"] as? String == "ui-verify-diff",
          params["entryId"] as? String == "diff-preview",
          params["itemId"] as? String == "edit"
        {
          let result = try JSONSerialization.data(withJSONObject: [
            "itemId": "edit",
            "rev": 1,
            "truncated": false,
            "blocks": [[
              "type": "diff",
              "path": "src/inline.ts",
              "oldText": "export const greeting = 'hi'\n",
              "newText": "export const greeting = 'hello'\n",
            ]],
          ])
          promise.resolve(String(decoding: result, as: UTF8.self))
          return
        }
        self.dataRuntime.itemDetail(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("respondSessionPermission") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.sessionWrite(RuntimeContract.Calls.RespondPermission.self, payload: payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("turnDiff") { (payload: String, promise: Promise) in
      try MainActor.assumeIsolated {
        if LodyUIVerify.enabled,
          let data = payload.data(using: .utf8),
          let params = try? JSONSerialization.jsonObject(with: data) as? [String: String],
          params["sessionId"] == "ui-verify-diff", params["entryId"] == "diff-preview",
          let path = params["path"], ["docs/superpowers/.diff-check.md", "src/very-long-directory-name/nested/components/another-long-file-name.ts", "docs/interactive.html"].contains(path) {
          let added = path.hasSuffix(".ts")
            ? """
              import { readFileSync } from 'node:fs';
              import { hashPassword } from './auth/password.mjs';
              import pg from 'pg';

              const password = readFileSync(new URL('./.tmp-alice.secret', import.meta.url), 'utf8').trim();
              const hash = await hashPassword(password);
              const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
              await client.connect();
              const r = await client.query(
                `UPDATE auth_account SET password_hash = $1 WHERE email = $2 AND deleted_at IS NULL RETURNING id`,
                [hash, 'alice@test.dev'],
              );
              console.log(r.rowCount, r.rows[0]?.id);
              await client.end();
              """
            : "a\nhello\nc\n"
          let contents = try JSONSerialization.data(withJSONObject: [
            "old": path.hasSuffix(".ts") ? "" : "a\nb\nc\n",
            "new": added,
          ])
          let handle = ContentStore.shared.put(StoredContent(data: contents, kind: "diff", path: path, session: "ui-verify-diff", mimeType: nil))
          let result = try JSONSerialization.data(withJSONObject: ["status": "ok", "handle": handle, "base": "turn", "oldKind": "text", "newKind": "text", "add": 1, "del": 1])
          promise.resolve(String(decoding: result, as: UTF8.self))
          return
        }
        self.dataRuntime.turnDiff(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("workspaceChanges") { (payload: String, promise: Promise) in MainActor.assumeIsolated { self.dataRuntime.workspaceChanges(payload, promise: promise) } }.runOnQueue(.main)
    AsyncFunction("fileDiff") { (payload: String, promise: Promise) in
      try MainActor.assumeIsolated {
        if LodyUIVerify.enabled,
          let params = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: String],
          params["sessionId"] == "ui-verify-workspace", let path = params["path"] {
          let contents = try JSONSerialization.data(withJSONObject: ["old": "export const greeting = 'hi';\n", "new": "export const greeting = 'hello';\n"])
          let handle = ContentStore.shared.put(StoredContent(data: contents, kind: "diff", path: path, session: "ui-verify-workspace", mimeType: nil))
          let result = try JSONSerialization.data(withJSONObject: ["status": "ok", "path": path, "handle": handle, "base": "current", "oldKind": "text", "newKind": "text", "add": 1, "del": 1])
          promise.resolve(String(decoding: result, as: UTF8.self))
          return
        }
        self.dataRuntime.fileDiff(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("readFile") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated {
        let runtime = self.dataRuntime
        Task { @MainActor in
          do {
            guard let args = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let sessionId = args["sessionId"] as? String,
              let path = args["path"] as? String
            else {
              throw NSError(domain: "LodyKit.FilePreview", code: 3)
            }
            promise.resolve(try await FilePreview.read(sessionId: sessionId, path: path, runtime: runtime))
          } catch {
            promise.reject(error as NSError)
          }
        }
      }
    }.runOnQueue(.main)
    AsyncFunction("openFile") { (sessionId: String, path: String, line: Int, promise: Promise) in
      MainActor.assumeIsolated {
        guard let controller = self.appContext?.utilities?.currentViewController() else {
          promise.reject(NSError(domain: "LodyKit.FilePreview", code: 2))
          return
        }
        let runtime = self.dataRuntime
        Task { @MainActor in
          let opened = await FilePreview.open(
            sessionId: sessionId, path: path, line: line, runtime: runtime, from: controller
          )
          promise.resolve(opened)
        }
      }
    }.runOnQueue(.main)
    AsyncFunction("mentionCatalog") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated {
        if let response = MentionFixture.response(payload) { promise.resolve(response); return }
        self.dataRuntime.mentionCatalog(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("listDir") { (payload: String, promise: Promise) in
      MainActor.assumeIsolated {
        if let response = FilePreviewFixture.response(payload, listing: true) { promise.resolve(response); return }
        self.dataRuntime.listDir(payload, promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("dataRuntimeStatus") { (promise: Promise) in
      promise.resolve(MainActor.assumeIsolated { self.dataRuntime.status() })
    }.runOnQueue(.main)
    AsyncFunction("debugProbeSchema") { (promise: Promise) in
      MainActor.assumeIsolated {
        self.dataRuntime.debugProbeSchema(promise: promise)
      }
    }.runOnQueue(.main)
    AsyncFunction("debugBackgroundDataRuntime") { (action: String, promise: Promise) in
      MainActor.assumeIsolated {
        self.dataRuntime.debugBackground(action, promise: promise)
      }
    }.runOnQueue(.main)
    Function("shareWriteCatalog") { (json: String) throws in try ShareStore.writeCatalog(json) }
    Function("shareWriteOptions") { (target: String, json: String) throws in
      guard let options = CreateJSON.decode(CreationOptions.self, json) else { throw CocoaError(.coderReadCorrupt) }
      try ShareStore.writeOptions(options, target: target)
    }
    Function("sharePending") { () -> String in CreateJSON.encode(ShareStore.pending()) }
    Function("shareAdopt") { (id: String) throws -> String in CreateJSON.encode(try ShareStore.adopt(id)) }
    Function("shareRemove") { (id: String) in ShareStore.remove(id) }
    AsyncFunction("decodeFlock") { (snapshot: String, updates: [String], mode: String, promise: Promise) in
      MainActor.assumeIsolated {
        guard snapshot.utf8.count + updates.reduce(0, { $0 + $1.utf8.count }) <= 12 * 1024 * 1024 else {
          promise.reject("DECODE_LIMIT", "workspace snapshot exceeds the decode limit"); return
        }
        _ = FlockDecoder(snapshot: snapshot, updates: updates, mode: mode) { result in
          switch result {
          case .success(let value): promise.resolve(value)
          case .failure: promise.reject("DECODE_FAILED", "workspace snapshot decode failed")
          }
        }
      }
    }.runOnQueue(.main)

    OnAppBecomesActive {
      self.onAppActive()
    }

    View(LodyComposerHandoffPOC.self) {
      Events("onClose")
    }
    View(LodyNativeShellPOC.self) {
      Events("onAction")
      Prop("collectionSidebar") { (view: LodyNativeShellPOC, value: Bool) in view.collectionSidebar = value }
    }
    View(LodyNativePagePOC.self) {
      Prop("layoutRoot") { (_: LodyNativePagePOC, _: Bool) in }
      Prop("pageKind") { (view: LodyNativePagePOC, value: String) in view.pageKind = value }
    }

    View(LodyNavigationHeaderView.self) {
      Events("onAction", "onSearch")
      Prop("itemsJSON") { (view: LodyNavigationHeaderView, value: String) in view.setItems(value) }
      Prop("leftItemsJSON") { (view: LodyNavigationHeaderView, value: String) in view.setLeftItems(value) }
      Prop("toolbarItemsJSON") { (view: LodyNavigationHeaderView, value: String) in view.setToolbarItems(value) }
      Prop("searchJSON") { (view: LodyNavigationHeaderView, value: String) in view.setSearch(value) }
      Prop("searchCommandJSON") { (view: LodyNavigationHeaderView, value: String) in view.setSearchCommand(value) }
      Prop("title") { (view: LodyNavigationHeaderView, value: String) in view.setTitle(value) }
      Prop("barHidden") { (view: LodyNavigationHeaderView, value: Bool) in view.setBarHidden(value) }
    }

    View(LodyMentionPickerView.self) {
      Events("onPick", "onQueryReset", "onRetry")
      Prop("configurationJSON") { (view: LodyMentionPickerView, value: String) in view.configure(value) }
    }

    View(LodyCreateSessionView.self) {
      Events("onRequest", "onPrefs", "onSelection", "onSubmit", "onRelayReady", "onMentionBrowse", "onCancel")
      Prop("configJSON") { (view: LodyCreateSessionView, value: String) in view.configure(value) }
      Prop("refreshKey") { (view: LodyCreateSessionView, value: String) in view.setRefreshKey(value) }
      Prop("responseJSON") { (view: LodyCreateSessionView, value: String) in view.respond(value) }
      Prop("composerRelay") { (view: LodyCreateSessionView, value: Bool) in view.setComposerRelay(value) }
      Prop("sendHandoff") { (view: LodyCreateSessionView, value: Bool?) in view.setSendHandoff(value ?? true) }
      Prop("restoreDraftToken") { (view: LodyCreateSessionView, value: Int) in view.restore(value) }
      Prop("mentionItemsJSON") { (view: LodyCreateSessionView, value: String) in view.setMentionItems(value) }
      Prop("mentionResultJSON") { (view: LodyCreateSessionView, value: String) in view.setMentionResult(value) }
    }

    View(LodyComposerView.self) {
      Prop("initialDraft") { (view: LodyComposerView, value: String) in view.composer.setInitialDraft(value) }
      Prop("initialAttachmentsJSON") { (view: LodyComposerView, value: String) in view.composer.setInitialAttachments(value) }
      Prop("autoFocus") { (view: LodyComposerView, value: Bool) in view.composer.autoFocus = value }
      Prop("inputIdentifier") { (view: LodyComposerView, value: String) in view.composer.setInputIdentifier(value) }
      Prop("composerRelay") { (view: LodyComposerView, value: Bool) in view.composerRelay = value }
      Prop("sendHandoff") { (view: LodyComposerView, value: Bool?) in view.composer.sendHandoff = value ?? true }
      Prop("scrollEdge") { (view: LodyComposerView, value: Bool) in view.scrollEdge = value }
      Events("onSend", "onRelayReady", "onHeightChange", "onComposerOptionChange", "onMentionBrowse")
      Prop("composerJSON") { (view: LodyComposerView, value: String) in view.composer.setComposerState(value) }
      Prop("mentionItemsJSON") { (view: LodyComposerView, value: String) in view.composer.setMentionItems(value) }
      Prop("mentionResultJSON") { (view: LodyComposerView, value: String) in view.composer.setMentionResult(value) }
      Prop("composerOptionsJSON") { (view: LodyComposerView, value: String) in view.composer.setComposerOptions(value) }
      Prop("restoreDraftToken") { (view: LodyComposerView, value: Int) in view.restoreDraft(token: value) }
    }

    Class(PreparedChatEntries.self) {}
    AsyncFunction("prepareChatEntries") { (json: String) in
      try PreparedChatEntries(json)
    }.runOnQueue(PreparedChatEntries.queue)

    View(LodySessionShareView.self) {
      Events("onAction")
      Prop("configurationJSON") { (view: LodySessionShareView, value: String) in view.configure(value) }
    }

    View(LodyMessageShareView.self) {
      Events("onState", "onBlocks")
      Prop("selectedJSON") { (view: LodyMessageShareView, value: String) in view.setSelected(value) }
      Prop("contentJSON") { (view: LodyMessageShareView, value: String) in view.setContent(value) }
      Prop("shareToken") { (view: LodyMessageShareView, value: Int) in view.share(value) }
      Prop("retryToken") { (view: LodyMessageShareView, value: Int) in view.retry(value) }
    }

    View(LodySimulatorView.self) {
      Prop("sourceJSON") { (view: LodySimulatorView, value: String) in view.setSource(value) }
      Prop("commandJSON") { (view: LodySimulatorView, value: String) in view.setCommand(value) }
    }

    View(LodyChatView.self) {
      Prop("simulatorPreviewJSON") { (view: LodyChatView, value: String) in view.setSimulatorPreview(value) }
      Prop("imageSharingEnabled") { (view: LodyChatView, value: Bool) in view.imageSharingEnabled = value }
      Prop("findRequestJSON") { (view: LodyChatView, value: String) in view.setFindRequest(value) }
      Prop("debugStreamBenchmarkRun") { (view: LodyChatView, value: Int) in
        guard value > 0 else { return }
        view.streamPerformanceProbe?.stop()
        view.streamPerformanceProbe = ChatStreamPerformanceProbe(view)
      }
      Prop("debugBenchmarkRun") { (view: LodyChatView, value: Int) in
        guard value > 0 else { return }
        view.performanceProbe?.stop()
        view.performanceProbe = ChatPerformanceProbe(view)
      }
      Events("onStop", "onSteer", "onSend", "onEditMessage", "onShareImage", "onTurnInfoPress", "onActivityPress", "onFilePress", "onTurnChangesPress", "onErrorRetry", "onPlanDecision", "onRetrySend", "onReconnect", "onTitlePress", "onComposerOptionChange", "onMentionBrowse", "onPreview", "onTitleMenu")
      Prop("editableMessageId") { (view: LodyChatView, value: String) in view.editableMessageID = value }
      Prop("editedMessageId") { (view: LodyChatView, value: String) in view.editedMessageID = value }
      Prop("navigationTitle") { (view: LodyChatView, value: String) in view.setNavigationTitle(value) }
      Prop("navigationSubtitle") { (view: LodyChatView, value: String) in view.setNavigationSubtitle(value) }
      Prop("navigationMachine") { (view: LodyChatView, value: String) in view.setNavigationMachine(value) }
      Prop("navigationMachineState") { (view: LodyChatView, value: String) in view.setNavigationMachineState(value) }
      Prop("navigationBranch") { (view: LodyChatView, value: String) in view.setNavigationBranch(value) }
      Prop("titleMenuJSON") { (view: LodyChatView, value: String) in view.setTitleMenu(value) }
      Prop("mentionRepository") { (view: LodyChatView, value: String) in view.mentionRepository = value }
      Prop("attachmentContextJSON") { (view: LodyChatView, value: String) in view.setAttachmentContext(value) }
      Prop("planDecisionJSON") { (view: LodyChatView, value: String) in view.setPlanDecisionState(value) }
      Prop("errorRetryJSON") { (view: LodyChatView, value: String) in view.setErrorRetryState(value) }
      Prop("turnInfoEnabled") { (view: LodyChatView, value: Bool) in view.turnInfoEnabled = value }
      Prop("entriesJSON") { (view: LodyChatView, value: String) in view.setEntries(value) }
      Prop("preparedEntries") { (view: LodyChatView, value: PreparedChatEntries?) in view.preparedEntries = value }
      OnViewDidUpdateProps { (view: LodyChatView) in view.scheduleUpdate() }
      Prop("pendingSendJSON") { (view: LodyChatView, value: String) in view.setPendingSendJSON(value) }
      Prop("processStartId") { (view: LodyChatView, value: String) in view.setProcessStartID(value) }
      Prop("processEntryId") { (view: LodyChatView, value: String) in view.setProcessEntryID(value) }
      Prop("composerJSON") { (view: LodyChatView, value: String) in view.setComposerState(value) }
      Prop("mentionItemsJSON") { (view: LodyChatView, value: String) in view.composer.setMentionItems(value) }
      Prop("mentionResultJSON") { (view: LodyChatView, value: String) in view.composer.setMentionResult(value) }
      Prop("composerOptionsJSON") { (view: LodyChatView, value: String) in view.setComposerOptions(value) }
      Prop("initialDraft") { (view: LodyChatView, value: String) in view.setInitialDraft(value) }
      Prop("draftKey") { (view: LodyChatView, value: String) in view.setDraftKey(value) }
      Prop("appendDraftJSON") { (view: LodyChatView, value: String) in view.composer.appendDraft(value) }
      Prop("initialAttachmentsJSON") { (view: LodyChatView, value: String) in view.setInitialAttachments(value) }
      Prop("clearDraftToken") { (view: LodyChatView, value: Int) in
        view.clearDraft(token: value)
      }
      Prop("restoreDraftToken") { (view: LodyChatView, value: Int) in view.restoreDraft(token: value) }
      Prop("emptyText") { (view: LodyChatView, value: String) in view.setEmptyText(value) }
    }

    View(LodyDiffSurface.self) {
      Prop("contentRevision") { (view: LodyDiffSurface, _: Double?) in view.setNeedsLayout() }
    }

    View(LodyDiffToolbar.self) {
      Events("onStyleChange")
      Prop("add") { (view: LodyDiffToolbar, value: Int?) in view.pendingAdd = value ?? 0; view.applyStats() }
      Prop("del") { (view: LodyDiffToolbar, value: Int?) in view.pendingDel = value ?? 0; view.applyStats() }
      Prop("base") { (view: LodyDiffToolbar, value: String?) in view.pendingBase = value ?? ""; view.applyStats() }
      Prop("diffStyle") { (view: LodyDiffToolbar, value: String?) in view.setStyle(value ?? "unified") }
    }

    View(LodyHTMLPreviewView.self) {
      Events("onResourceRequest", "onIssues", "onLoad", "onFail")
      Prop("handle") { (view: LodyHTMLPreviewView, value: String) in view.setHandle(value) }
      Prop("responsesJSON") { (view: LodyHTMLPreviewView, value: String) in view.setResponses(value) }
    }

    View(LodyMarkdownDocumentView.self) {
      Events("onFail", "onFilePress")
      Prop("handle") { (view: LodyMarkdownDocumentView, value: String) in view.setHandle(value) }
    }

    View(LodyInlineDiffView.self) {
      Events("onRender", "onFail")
      Prop("path") { (view: LodyInlineDiffView, value: String) in view.setPath(value) }
      Prop("oldText") { (view: LodyInlineDiffView, value: String?) in view.setOldText(value) }
      Prop("newText") { (view: LodyInlineDiffView, value: String?) in view.setNewText(value) }
    }

    View(LodyAppIconGrid.self) {
      Events("onSelect")
      Prop("items") { (view: LodyAppIconGrid, value: [LodyAppIconItem]) in view.setItems(value) }
      Prop("selected") { (view: LodyAppIconGrid, value: String) in view.setSelected(value) }
      Prop("pending") { (view: LodyAppIconGrid, value: String) in view.setPending(value) }
      Prop("enabled") { (view: LodyAppIconGrid, value: Bool) in view.setEnabled(value) }
    }

    View(LodyPagedList.self) {
      Events("onRowPress", "onPageChange")
      Prop("pages") { (view: LodyPagedList, pages: [LodyPagedPage]) in view.setPages(pages) }
      Prop("selectedPage") { (view: LodyPagedList, index: Int) in view.setSelectedPage(index) }
      Prop("pagingEnabled") { (view: LodyPagedList, enabled: Bool) in
        view.setPagingEnabled(enabled)
      }
      Prop("bottomInset") { (view: LodyPagedList, value: Double) in view.setBottomInset(CGFloat(value)) }
      Prop("transparent") { (view: LodyPagedList, transparent: Bool) in
        view.setTransparent(transparent)
      }
      Prop("accent") { (view: LodyPagedList, accent: String) in
        view.setAccent(accent)
      }
    }

    View(LodySidebar.self) {
      Events("onRowPress", "onRowAction")
      Prop("sections") { (view: LodySidebar, value: [LodyListSection]) in view.setSections(value) }
      Prop("selectedRowId") { (view: LodySidebar, value: String?) in view.setSelectedRowId(value ?? "") }
      Prop("placeholder") { (view: LodySidebar, value: String) in view.setPlaceholder(value) }
      Prop("accent") { (view: LodySidebar, value: String) in view.setAccent(value) }
      Prop("previewUserId") { (view: LodySidebar, value: String) in view.previewUserId = value }
      Prop("previewWorkspaceId") { (view: LodySidebar, value: String) in view.previewWorkspaceId = value }
    }

    View(LodyGroupedList.self) {
      Prop("bottomInset") { (view: LodyGroupedList, value: Double) in view.setBottomInset(CGFloat(value)) }
      Prop("contentStyle") { (view: LodyGroupedList, value: Bool) in
        view.setContentStyle(value)
      }
      Events("onRowPress", "onRowToggle", "onRowAction", "onReorder", "onRefresh", "onSegmentChange", "onSearchChange", "onNoticeAction", "onUnavailableAction")
      Prop("reordering") { (view: LodyGroupedList, value: Bool) in view.setReordering(value) }
      Prop("loading") { (view: LodyGroupedList, value: Bool) in view.setLoading(value) }
      Prop("notice") { (view: LodyGroupedList, value: LodyListNotice?) in view.setNotice(value) }
      Prop("unavailable") { (view: LodyGroupedList, value: LodyListUnavailable?) in view.setUnavailable(value) }
      Prop("segments") { (view: LodyGroupedList, labels: [String]) in view.setSegments(labels) }
      Prop("selectedSegment") { (view: LodyGroupedList, index: Int) in view.setSelectedSegment(index) }
      Prop("segmentsStyle") { (view: LodyGroupedList, value: String) in view.setSegmentsStyle(value) }
      Prop("segmentsDone") { (view: LodyGroupedList, value: [Bool]) in view.setSegmentsDone(value) }
      Prop("searchPlaceholder") { (view: LodyGroupedList, value: String) in view.setSearchPlaceholder(value) }
      Prop("searchText") { (view: LodyGroupedList, value: String) in view.setSearchText(value) }
      Prop("sections") { (view: LodyGroupedList, sections: [LodyListSection]) in
        view.setSections(sections)
      }
      Prop("segmentsUseSearchScope") { (view: LodyGroupedList, value: Bool) in
        view.setSegmentsUseSearchScope(value)
      }
      Prop("transparent") { (view: LodyGroupedList, transparent: Bool) in
        view.setTransparent(transparent)
      }
      Prop("accent") { (view: LodyGroupedList, accent: String) in
        view.setAccent(accent)
      }
      Prop("refreshEnabled") { (view: LodyGroupedList, enabled: Bool) in
        view.setRefreshEnabled(enabled)
      }
      Prop("refreshing") { (view: LodyGroupedList, refreshing: Bool) in
        view.setRefreshing(refreshing)
      }
      Prop("placeholder") { (view: LodyGroupedList, placeholder: String) in
        view.setPlaceholder(placeholder)
      }
      Prop("previewUserId") { (view: LodyGroupedList, value: String) in
        view.setPreviewUserId(value)
      }
      Prop("previewWorkspaceId") { (view: LodyGroupedList, value: String) in
        view.setPreviewWorkspaceId(value)
      }
    }
    View(LodyMenuButton.self) {
      Events("onSelect", "onSize")
      Prop("status") { (view: LodyMenuButton, value: String) in view.setStatus(value) }
      Prop("accessibilityName") { (view: LodyMenuButton, name: String) in
        view.setAccessibilityName(name)
      }
      Prop("avatar") { (view: LodyMenuButton, avatar: LodyMenuAvatar) in
        view.setAvatar(avatar)
      }
      Prop("label") { (view: LodyMenuButton, label: String) in
        view.setLabel(label)
      }
      Prop("items") { (view: LodyMenuButton, items: [LodyMenuItem]) in
        view.setItems(items)
      }
    }

    View(LodyCloseButton.self) {
      Events("onClose")
      Prop("label") { (view: LodyCloseButton, label: String) in
        view.setAccessibilityName(label)
      }
    }

    View(LodySymbolButton.self) {
      Prop("glass") { (view: LodySymbolButton, value: Bool) in
        view.setGlass(value)
      }
      Events("onSymbolPress", "onSymbolLongPress")
      Prop("imageAsset") { (view: LodySymbolButton, imageAsset: String) in
        view.setImageAsset(imageAsset)
      }
      Prop("symbol") { (view: LodySymbolButton, symbol: String) in
        view.setSymbol(symbol)
      }
      Prop("accessibilityName") { (view: LodySymbolButton, name: String) in
        view.setAccessibilityName(name)
      }
      Prop("prominent") { (view: LodySymbolButton, prominent: Bool) in
        view.setProminent(prominent)
      }
      Prop("disabled") { (view: LodySymbolButton, disabled: Bool) in
        view.setDisabled(disabled)
      }
      Prop("loading") { (view: LodySymbolButton, loading: Bool) in
        view.setLoading(loading)
      }
      Prop("tint") { (view: LodySymbolButton, tint: String) in
        view.setTint(tint)
      }
      Prop("longPress") { (view: LodySymbolButton, value: Bool) in
        view.setLongPress(value)
      }
    }

    View(LodySearchToolbar.self) {
      Events("onSearchChange", "onAction")
      Prop("placeholder") { (view: LodySearchToolbar, value: String) in
        view.setPlaceholder(value)
      }
      Prop("actionAccessibilityName") { (view: LodySearchToolbar, value: String) in
        view.setActionAccessibilityName(value)
      }
      Prop("tint") { (view: LodySearchToolbar, value: String) in
        view.setTint(value)
      }
      Prop("visible") { (view: LodySearchToolbar, value: Bool) in
        view.setVisible(value)
      }
    }

    View(LodyLayoutProbe.self) {
      Events("onTraits")
    }

    View(LodySplitView.self) {
      Events("onColumnLayout")
      Prop("detailRequest") { (view: LodySplitView, value: Int) in
        view.setDetailRequest(value)
      }
      Prop("layoutMode") { (view: LodySplitView, value: String) in
        view.setLayoutMode(value)
      }
      Prop("panelOpen") { (view: LodySplitView, value: Bool) in
        view.setPanelOpen(value)
      }
    }

    View(LodyEmbeddedSheet.self) {
      Events("onDismiss")
      Prop("mediumFraction") { (view: LodyEmbeddedSheet, value: Double) in
        view.setMediumFraction(value)
      }
      Prop("dismissRequest") { (view: LodyEmbeddedSheet, value: Int) in
        view.setDismissRequest(value)
      }
      Prop("grabberAccessibilityIdentifier") { (view: LodyEmbeddedSheet, value: String) in
        view.setGrabberAccessibilityIdentifier(value)
      }
      Prop("grabberAccessibility") { (view: LodyEmbeddedSheet, value: [String: String]) in
        view.setGrabberAccessibility(
          label: value["label"] ?? "",
          medium: value["medium"] ?? "",
          large: value["large"] ?? ""
        )
      }
    }

    View(LodySymbolView.self) {
      Prop("symbol") { (view: LodySymbolView, symbol: String) in
        view.setSymbol(symbol)
      }
      Prop("pointSize") { (view: LodySymbolView, size: Double) in
        view.setPointSize(size)
      }
      Prop("tint") { (view: LodySymbolView, tint: String) in
        view.setTint(tint)
      }
    }

    View(LodyContextMenu.self) {
      Events("onAction")
      Prop("actions") { (view: LodyContextMenu, actions: [LodyContextMenuAction]) in
        view.setActions(actions)
      }
    }

    View(LodyPressable.self) {
      Events("onNativePress")
      Prop("pressScale") { (view: LodyPressable, scale: Double) in
        view.setPressScale(scale)
      }
      Prop("haptic") { (view: LodyPressable, haptic: Bool) in
        view.setHaptic(haptic)
      }
      Prop("disabled") { (view: LodyPressable, disabled: Bool) in
        view.setDisabled(disabled)
      }
    }

    View(LodyGlassSurface.self) {
      Prop("radius") { (view: LodyGlassSurface, radius: Double) in
        view.setRadius(radius)
      }
      Prop("tint") { (view: LodyGlassSurface, tint: String) in
        view.setTint(tint)
      }
    }
  }
}
