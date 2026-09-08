import ExpoModulesCore
import UIKit
import SafariServices

public final class LodyKitModule: Module {
  private let localStore = LocalStore.shared
  private var authBrowser: SFSafariViewController?

  private lazy var dataRuntime = DataRuntime(localStore: localStore) { [weak self] event in self?.sendEvent("onDataRuntime", event) }

  public func definition() -> ModuleDefinition {
    Name("LodyKit")

    Events("onAppActive", "onDataRuntime", "onPushClick")
    OnCreate {
      PushNotifications.shared.onClickAvailable = { [weak self] in self?.sendEvent("onPushClick", [:]) }
      ContentPreview.clearAll()
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--lody-offline") {
        URLProtocol.registerClass(OfflineProbe.self)
      }
      #endif
    }

    AsyncFunction("watchCatalog") { (workspace: String, owner: String, userId: String) in
      guard !workspace.isEmpty, !owner.isEmpty, !userId.isEmpty else { throw NSError(domain: "InvalidSubscription", code: 1) }
      self.dataRuntime.start(workspace: workspace, owner: owner, userId: userId)
    }.runOnQueue(.main)
    AsyncFunction("unwatchCatalog") { (owner: String) in self.dataRuntime.stop(owner: owner) }.runOnQueue(.main)
    AsyncFunction("watchSession") { (id: String) in self.dataRuntime.openSession(id) }.runOnQueue(.main)
    AsyncFunction("unwatchSession") { (id: String) in self.dataRuntime.closeSession(id) }.runOnQueue(.main)
    AsyncFunction("sessionCreationOptions") { (payload: String, promise: Promise) in self.dataRuntime.command("creationOptions", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("localProjects") { (payload: String, promise: Promise) in self.dataRuntime.command("localProjects", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("remoteSettings") { (payload: String, promise: Promise) in self.dataRuntime.command("remoteSettings", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("createSession") { (payload: String, promise: Promise) in self.dataRuntime.command("createSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("archiveSession") { (payload: String, promise: Promise) in self.dataRuntime.command("archiveSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("pinSession") { (payload: String, promise: Promise) in self.dataRuntime.command("pinSession", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("controlSessionTurn") { (payload: String, promise: Promise) in self.dataRuntime.command("controlTurn", payload: payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("sendSessionTurn") { (payload: String, promise: Promise) in self.dataRuntime.sendTurn(payload, promise: promise) }.runOnQueue(.main)
    AsyncFunction("sessionItemDetail") { (payload: String, promise: Promise) in self.dataRuntime.command("itemDetail", payload: payload, promise: promise) }.runOnQueue(.main)
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
    AsyncFunction("readContentText") { (handle: String) -> String? in
      ContentStore.shared.get(handle).flatMap { String(data: $0.data, encoding: .utf8) }
    }.runOnQueue(.main)
    AsyncFunction("previewContent") { (handle: String) in
      guard let controller = self.appContext?.utilities?.currentViewController() else {
        throw NSError(domain: "LodyKit.ContentPreview", code: 2)
      }
      try ContentPreview.present(handle: handle, from: controller)
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
    AsyncFunction("debugHangDataRuntime") {
      #if DEBUG
      self.dataRuntime.debugHang()
      #endif
    }.runOnQueue(.main)
    AsyncFunction("debugRestartDataRuntime") {
      #if DEBUG
      self.dataRuntime.debugRestart()
      #endif
    }.runOnQueue(.main)
    OnDestroy { DispatchQueue.main.async { self.dataRuntime.stop(); PushNotifications.shared.onClickAvailable = nil } }

    AsyncFunction("readLocalStartup") { try self.localStore.startup() }.runOnQueue(LocalStore.queue)
    AsyncFunction("readLocalValue") { (key: String) in try self.localStore.read(key) }.runOnQueue(LocalStore.queue)
    AsyncFunction("writeLocalValue") { (key: String, value: String) in try self.localStore.write(key, value) }.runOnQueue(LocalStore.queue)
    AsyncFunction("clearLocalValues") { (promise: Promise) in
      // Stop producers before clearing their queued writes, including background Sessions.
      self.dataRuntime.stop()
      LocalStore.queue.async {
        do { try self.localStore.clear(); promise.resolve(nil) }
        catch { promise.reject(error) }
      }
    }.runOnQueue(.main)

    AsyncFunction("verifyPushSubscription") {
      #if DEBUG
      guard let controller = self.appContext?.utilities?.currentViewController() else { return }
      PushNotifications.shared.onRegistered = { [weak controller] in
        if let controller { PushNotifications.shared.verify(from: controller) }
      }
      PushNotifications.shared.verify(from: controller)
      #endif
    }.runOnQueue(.main)
    AsyncFunction("setPushUser") { (userId: String?) in PushNotifications.shared.identify(userId) }.runOnQueue(.main)
    AsyncFunction("pushStatus") { (promise: Promise) in PushNotifications.shared.status { promise.resolve($0) } }.runOnQueue(.main)
    AsyncFunction("requestPushPermission") { (promise: Promise) in PushNotifications.shared.request { promise.resolve($0) } }.runOnQueue(.main)
    AsyncFunction("pendingPushClick") { PushNotifications.shared.readPending() }.runOnQueue(.main)
    AsyncFunction("acknowledgePushClick") { (id: String) in PushNotifications.shared.acknowledge(id) }.runOnQueue(.main)
    AsyncFunction("setPushVisibleRoute") { (route: String) in PushNotifications.shared.visibleRoute = route }.runOnQueue(.main)

    AsyncFunction("readAuthToken") { try AuthKeychain.read() }.runOnQueue(.main)
    AsyncFunction("saveAuthToken") { (token: String) in try AuthKeychain.save(token) }.runOnQueue(.main)
    AsyncFunction("clearAuthToken") { self.dataRuntime.stop(); PushNotifications.shared.identify(nil); try AuthKeychain.clear() }.runOnQueue(.main)
    AsyncFunction("openAuthBrowser") { (address: String) in
      guard let url = URL(string: address), url.scheme == "https", url.host == "lody.ai",
            url.user == nil, url.password == nil,
            let controller = self.appContext?.utilities?.currentViewController() else {
        throw NSError(domain: "LodyKit.AuthBrowser", code: 1)
      }
      let browser = SFSafariViewController(url: url)
      self.authBrowser = browser
      controller.present(browser, animated: true)
    }.runOnQueue(.main)
    AsyncFunction("closeAuthBrowser") {
      self.authBrowser?.dismiss(animated: true)
      self.authBrowser = nil
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
      self.sendEvent("onAppActive", [:])
    }

    Function("showToast") { (message: String, kind: String) in
      if Thread.isMainThread {
        LodyToastOverlay.shared.show(message: message, kind: kind)
      } else {
        DispatchQueue.main.async {
          LodyToastOverlay.shared.show(message: message, kind: kind)
        }
      }
    }

    Function("showSessionBanner") { (title: String, kind: String) in
      if Thread.isMainThread {
        LodyToastOverlay.shared.showBanner(title: title, kind: kind)
      } else {
        DispatchQueue.main.async {
          LodyToastOverlay.shared.showBanner(title: title, kind: kind)
        }
      }
    }

    Function("dismissSessionBanner") {
      if Thread.isMainThread {
        LodyToastOverlay.shared.dismissBanner()
      } else {
        DispatchQueue.main.async {
          LodyToastOverlay.shared.dismissBanner()
        }
      }
    }

    AsyncFunction("selectionFeedback") {
      UISelectionFeedbackGenerator().selectionChanged()
    }.runOnQueue(.main)

    Function("saveInboxView") { (index: Int) in
      UserDefaults.standard.set(index == 1 ? 1 : 0, forKey: "inboxView")
    }

    Function("readInboxExpansion") {
      UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
    }
    Function("saveInboxExpansion") { (projectID: String, expanded: Bool) in
      var values = UserDefaults.standard.dictionary(forKey: "inboxExpansion") as? [String: Bool] ?? [:]
      values[projectID] = expanded
      UserDefaults.standard.set(values, forKey: "inboxExpansion")
    }

    Constants {
      var offlineProbe = false
      #if DEBUG
      offlineProbe = ProcessInfo.processInfo.arguments.contains("--lody-offline")
      #endif
      return ["initialInboxView": UserDefaults.standard.integer(forKey: "inboxView"), "runtimeInfo": [
        "moduleName": "LodyKit",
        "offlineProbe": offlineProbe,
        "systemVersion": UIDevice.current.systemVersion,
      ]]
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

    View(LodyDiffView.self) {
      Events("onRender", "onFail")
      Prop("path") { (view: LodyDiffView, value: String) in view.setPath(value) }
      Prop("oldText") { (view: LodyDiffView, value: String?) in view.setOldText(value) }
      Prop("newText") { (view: LodyDiffView, value: String?) in view.setNewText(value) }
      Prop("handle") { (view: LodyDiffView, value: String?) in view.setHandle(value ?? "") }
      Prop("diffStyle") { (view: LodyDiffView, value: String?) in view.setStyle(value ?? "unified") }
      Prop("scrollEnabled") { (view: LodyDiffView, value: Bool?) in view.setScrollEnabled(value ?? true) }
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
}
