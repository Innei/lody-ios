import ExpoModulesCore
import UIKit
import SafariServices

@Record
struct LodyRuntimeInfo {
  var moduleName: String = "LodyKit"
  var offlineProbe: Bool = false
  var systemVersion: String = ""
}

@ExpoModule("LodyKit")
public final class LodyKitModule: Module {
  private let localStore = LocalStore.shared
  private var authBrowser: SFSafariViewController?

  private lazy var dataRuntime = DataRuntime(localStore: localStore) { [weak self] event in self?.sendEvent("onDataRuntime", event) }

  @Event("onAppActive")
  var onAppActive: () -> Void

  @JS
  var initialInboxView: Int {
    UserDefaults.standard.integer(forKey: "inboxView")
  }

  @JS
  var runtimeInfo: LodyRuntimeInfo {
    var offlineProbe = false
    #if DEBUG
    offlineProbe = ProcessInfo.processInfo.arguments.contains("--lody-offline")
    #endif
    return LodyRuntimeInfo(
      moduleName: "LodyKit",
      offlineProbe: offlineProbe,
      systemVersion: UIDevice.current.systemVersion
    )
  }

  public override func didCreate() {
    ContentPreview.clearAll()
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--lody-offline") {
      URLProtocol.registerClass(OfflineProbe.self)
    }
    #endif
  }

  public override func willDestroy() {
    DispatchQueue.main.async { self.dataRuntime.stop() }
  }

  @JS
  func watchCatalog(workspace: String, owner: String, userId: String) async throws {
    try await runOnMain {
      guard !workspace.isEmpty, !owner.isEmpty, !userId.isEmpty else { throw NSError(domain: "InvalidSubscription", code: 1) }
      self.dataRuntime.start(workspace: workspace, owner: owner, userId: userId)
    }
  }

  @JS
  func unwatchCatalog(owner: String) async {
    await runOnMain { self.dataRuntime.stop(owner: owner) }
  }

  @JS
  func watchSession(id: String) async {
    await runOnMain { self.dataRuntime.openSession(id) }
  }

  @JS
  func unwatchSession(id: String) async {
    await runOnMain { self.dataRuntime.closeSession(id) }
  }

  @JS
  func readContentText(handle: String) async -> String? {
    await runOnMain {
      ContentStore.shared.get(handle).flatMap { String(data: $0.data, encoding: .utf8) }
    }
  }

  @JS
  func previewContent(handle: String) async throws {
    try await runOnMain {
      guard let controller = self.appContext?.utilities?.currentViewController() else {
        throw NSError(domain: "LodyKit.ContentPreview", code: 2)
      }
      try ContentPreview.present(handle: handle, from: controller)
    }
  }

  @JS
  func debugHangDataRuntime() async {
    await runOnMain {
      #if DEBUG
      self.dataRuntime.debugHang()
      #endif
    }
  }

  @JS
  func debugRestartDataRuntime() async {
    await runOnMain {
      #if DEBUG
      self.dataRuntime.debugRestart()
      #endif
    }
  }

  @JS
  func readLocalStartup() async throws -> [String: String] {
    try await runOnStore { try self.localStore.startup() }
  }

  @JS
  func readLocalValue(key: String) async throws -> String? {
    try await runOnStore { try self.localStore.read(key) }
  }

  @JS
  func writeLocalValue(key: String, value: String) async throws {
    try await runOnStore { try self.localStore.write(key, value) }
  }

  @JS
  func readAuthToken() async throws -> String? {
    try await runOnMain { try AuthKeychain.read() }
  }

  @JS
  func saveAuthToken(token: String) async throws {
    try await runOnMain { try AuthKeychain.save(token) }
  }

  @JS
  func clearAuthToken() async throws {
    try await runOnMain {
      self.dataRuntime.stop()
      try AuthKeychain.clear()
    }
  }

  @JS
  func openAuthBrowser(address: String) async throws {
    try await runOnMain {
      guard let url = URL(string: address), url.scheme == "https", url.host == "lody.ai",
            url.user == nil, url.password == nil,
            let controller = self.appContext?.utilities?.currentViewController() else {
        throw NSError(domain: "LodyKit.AuthBrowser", code: 1)
      }
      let browser = SFSafariViewController(url: url)
      self.authBrowser = browser
      controller.present(browser, animated: true)
    }
  }

  @JS
  func closeAuthBrowser() async {
    await runOnMain {
      self.authBrowser?.dismiss(animated: true)
      self.authBrowser = nil
    }
  }

  @JS
  func selectionFeedback() async {
    await runOnMain { UISelectionFeedbackGenerator().selectionChanged() }
  }

  @JS
  func showToast(message: String, kind: String) {
    if Thread.isMainThread {
      LodyToastOverlay.shared.show(message: message, kind: kind)
    } else {
      DispatchQueue.main.async {
        LodyToastOverlay.shared.show(message: message, kind: kind)
      }
    }
  }

  @JS
  func showSessionBanner(title: String, kind: String) {
    if Thread.isMainThread {
      LodyToastOverlay.shared.showBanner(title: title, kind: kind)
    } else {
      DispatchQueue.main.async {
        LodyToastOverlay.shared.showBanner(title: title, kind: kind)
      }
    }
  }

  @JS
  func dismissSessionBanner() {
    if Thread.isMainThread {
      LodyToastOverlay.shared.dismissBanner()
    } else {
      DispatchQueue.main.async {
        LodyToastOverlay.shared.dismissBanner()
      }
    }
  }

  @JS
  func saveInboxView(index: Int) {
    UserDefaults.standard.set(index == 1 ? 1 : 0, forKey: "inboxView")
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

  public func definition() -> ModuleDefinition {
    Events("onDataRuntime")

    AsyncFunction("sessionCreationOptions") { (payload: String, promise: Promise) in self.dataRuntime.command("creationOptions", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("localProjects") { (payload: String, promise: Promise) in self.dataRuntime.command("localProjects", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("remoteSettings") { (payload: String, promise: Promise) in self.dataRuntime.command("remoteSettings", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("createSession") { (payload: String, promise: Promise) in self.dataRuntime.command("createSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("archiveSession") { (payload: String, promise: Promise) in self.dataRuntime.command("archiveSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("pinSession") { (payload: String, promise: Promise) in self.dataRuntime.command("pinSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("controlSessionTurn") { (payload: String, promise: Promise) in self.dataRuntime.command("controlTurn", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("sendSessionTurn") { (payload: String, promise: Promise) in self.dataRuntime.sendTurn(payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("sessionItemDetail") { (payload: String, promise: Promise) in
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-verify"),
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
      #endif
      self.dataRuntime.command("itemDetail", payload: payload, promise: promise)
    }.runOnQueue(.main)
    AsyncFunction("respondSessionPermission") { (payload: String, promise: Promise) in self.dataRuntime.command("respondPermission", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("turnDiff") { (payload: String, promise: Promise) in
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-verify"),
        let data = payload.data(using: .utf8),
        let params = try? JSONSerialization.jsonObject(with: data) as? [String: String],
        params["sessionId"] == "ui-verify-diff", params["entryId"] == "diff-preview",
        let path = params["path"], ["docs/superpowers/.diff-check.md", "src/very-long-directory-name/nested/components/another-long-file-name.ts"].contains(path) {
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
      #endif
      self.dataRuntime.command("turnDiff", payload: payload, promise: promise)
    }.runOnQueue(.main)
    AsyncFunction("fileDiff") { (payload: String, promise: Promise) in self.dataRuntime.command("fileDiff", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("readFile") { (payload: String, promise: Promise) in
      #if DEBUG
      if let response = FilePreviewFixture.response(payload) { promise.resolve(response); return }
      #endif
      self.dataRuntime.command("readFile", payload: payload, promise: promise)
    }.runOnQueue(.main)
    AsyncFunction("listDir") { (payload: String, promise: Promise) in
      #if DEBUG
      if let response = FilePreviewFixture.response(payload, listing: true) { promise.resolve(response); return }
      #endif
      self.dataRuntime.command("listDir", payload: payload, promise: promise)
    }.runOnQueue(.main)
    AsyncFunction("dataRuntimeStatus") { self.dataRuntime.status() }.runOnQueue(.main)
    AsyncFunction("debugProbeSchema") { (promise: Promise) in
      #if DEBUG
      self.dataRuntime.debugProbeSchema(promise: promise)
      #else
      promise.resolve("{}")
      #endif
    }.runOnQueue(.main)
    AsyncFunction("debugBackgroundDataRuntime") { (action: String, promise: Promise) in
      #if DEBUG
      self.dataRuntime.debugBackground(action, promise: promise)
      #else
      promise.resolve("{}")
      #endif
    }.runOnQueue(.main)
    AsyncFunction("clearLocalValues") { (promise: Promise) in
      // Stop producers before clearing their queued writes, including background Sessions.
      self.dataRuntime.stop()
      LocalStore.queue.async {
        do { try self.localStore.clear(); promise.resolve(nil) }
        catch { promise.reject(error) }
      }
    }.runOnQueue(.main)
    AsyncFunction("decodeFlock") { (snapshot: String, updates: [String], mode: String, promise: Promise) in
      guard snapshot.utf8.count + updates.reduce(0, { $0 + $1.utf8.count }) <= 12 * 1024 * 1024 else {
        promise.reject("DECODE_LIMIT", "workspace snapshot exceeds the decode limit"); return
      }
      _ = FlockDecoder(snapshot: snapshot, updates: updates, mode: mode) { result in
        switch result {
        case .success(let value): promise.resolve(value)
        case .failure: promise.reject("DECODE_FAILED", "workspace snapshot decode failed")
        }
      }
    }.runOnQueue(.main)

    OnAppBecomesActive {
      self.onAppActive()
    }

    View(LodyComposerView.self) {
      Prop("scrollEdge") { (view: LodyComposerView, value: Bool) in view.scrollEdge = value }
      Events("onSend", "onHeightChange", "onComposerOptionChange")
      Prop("composerJSON") { (view: LodyComposerView, value: String) in view.composer.setComposerState(value) }
      Prop("composerOptionsJSON") { (view: LodyComposerView, value: String) in view.composer.setComposerOptions(value) }
      Prop("restoreDraftToken") { (view: LodyComposerView, value: Int) in view.composer.restoreDraft(token: value) }
    }

    View(LodyChatView.self) {
      #if DEBUG
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
      #endif
      Events("onStop", "onSteer", "onSend", "onActivityPress", "onFilePress", "onTurnChangesPress", "onReconnect", "onTitlePress", "onComposerOptionChange")
      Prop("navigationTitle") { (view: LodyChatView, value: String) in view.setNavigationTitle(value) }
      Prop("navigationSubtitle") { (view: LodyChatView, value: String) in view.setNavigationSubtitle(value) }
      Prop("attachmentContextJSON") { (view: LodyChatView, value: String) in view.setAttachmentContext(value) }
      Prop("entriesJSON") { (view: LodyChatView, value: String) in view.setEntries(value) }
      Prop("pendingSendJSON") { (view: LodyChatView, value: String) in view.setPendingSendJSON(value) }
      Prop("processStartId") { (view: LodyChatView, value: String) in view.setProcessStartID(value) }
      Prop("processEntryId") { (view: LodyChatView, value: String) in view.setProcessEntryID(value) }
      Prop("composerJSON") { (view: LodyChatView, value: String) in view.setComposerState(value) }
      Prop("composerOptionsJSON") { (view: LodyChatView, value: String) in view.setComposerOptions(value) }
      Prop("initialDraft") { (view: LodyChatView, value: String) in view.setInitialDraft(value) }
      Prop("draftKey") { (view: LodyChatView, value: String) in view.setDraftKey(value) }
      Prop("initialAttachmentsJSON") { (view: LodyChatView, value: String) in view.setInitialAttachments(value) }
      Prop("clearDraftToken") { (view: LodyChatView, value: Int) in
        view.clearDraft(token: value)
      }
      Prop("restoreDraftToken") { (view: LodyChatView, value: Int) in view.restoreDraft(token: value) }
      Prop("emptyText") { (view: LodyChatView, value: String) in view.setEmptyText(value) }
    }

    View(LodyDiffToolbar.self) {
      Events("onStyleChange")
      Prop("add") { (view: LodyDiffToolbar, value: Int?) in view.pendingAdd = value ?? 0; view.applyStats() }
      Prop("del") { (view: LodyDiffToolbar, value: Int?) in view.pendingDel = value ?? 0; view.applyStats() }
      Prop("base") { (view: LodyDiffToolbar, value: String?) in view.pendingBase = value ?? ""; view.applyStats() }
      Prop("diffStyle") { (view: LodyDiffToolbar, value: String?) in view.setStyle(value ?? "unified") }
    }

    View(LodyCodeView.self) {
      Events("onFail", "onFilePress")
      Prop("renderMarkdown") { (view: LodyCodeView, value: Bool) in view.setMarkdown(value) }
      Prop("line") { (view: LodyCodeView, value: Int) in view.setLine(value) }
      Prop("handle") { (view: LodyCodeView, value: String) in view.setHandle(value) }
      Prop("path") { (view: LodyCodeView, value: String) in view.setPath(value) }
    }

    View(LodyInlineDiffView.self) {
      Events("onRender", "onFail")
      Prop("path") { (view: LodyInlineDiffView, value: String) in view.setPath(value) }
      Prop("oldText") { (view: LodyInlineDiffView, value: String?) in view.setOldText(value) }
      Prop("newText") { (view: LodyInlineDiffView, value: String?) in view.setNewText(value) }
    }

    View(LodyGroupedList.self) {
      Prop("bottomInset") { (view: LodyGroupedList, value: Double) in view.setBottomInset(CGFloat(value)) }
      Prop("contentStyle") { (view: LodyGroupedList, value: Bool) in
        view.setContentStyle(value)
      }
      Events("onRowPress", "onRowAction", "onRefresh", "onSegmentChange")
      Prop("segments") { (view: LodyGroupedList, labels: [String]) in view.setSegments(labels) }
      Prop("selectedSegment") { (view: LodyGroupedList, index: Int) in view.setSelectedSegment(index) }
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
      Events("onSymbolPress", "onSymbolLongPress")
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
      Prop("tint") { (view: LodySymbolButton, tint: String) in
        view.setTint(tint)
      }
      Prop("longPress") { (view: LodySymbolButton, value: Bool) in
        view.setLongPress(value)
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

  private func runOnMain<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        do { continuation.resume(returning: try work()) }
        catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func runOnMain<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume(returning: work())
      }
    }
  }

  private func runOnStore<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      LocalStore.queue.async {
        do { continuation.resume(returning: try work()) }
        catch { continuation.resume(throwing: error) }
      }
    }
  }
}
