// Copyright 2015-present 650 Industries. All rights reserved.

internal import React
import ExpoModulesCore
import WebKit

// `WKWebView` subclass that can hide the keyboard input accessory bar.
// https://stackoverflow.com/a/58001395/7070640
final class DomWKWebView: WKWebView {
  var hidesInputAccessoryView = false

  override var inputAccessoryView: UIView? {
    hidesInputAccessoryView ? nil : super.inputAccessoryView
  }
}

internal final class DomWebView: ExpoView, UIScrollViewDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, RCTAutoInsetsProtocol {
  // Created on first prop sync — `WKWebViewConfiguration` is copied at init,
  // so init-only props need to land before `WKWebView()` is called.
  private(set) var webView: DomWKWebView?
  // swiftlint:disable:next implicitly_unwrapped_optional
  private(set) var id: WebViewId!

  private var source: DomWebViewSource?
  private var injectedJS: WKUserScript?
  private var injectedJSBeforeContentLoaded: WKUserScript?
  private var injectedObjectJsonScript: WKUserScript?
  private var needsResetupScripts = false

  // MARK: - WKWebViewConfiguration props (init-only)

  var allowsInlineMediaPlayback: Bool = true
  var mediaPlaybackRequiresUserAction: Bool = true
  var allowsPictureInPictureMediaPlayback: Bool = true
  var allowsAirPlayForMediaPlayback: Bool = true

  // MARK: - Bridge props

  var useExpoModulesBridge: Bool = false {
    didSet { needsResetupScripts = true }
  }

  // Only the full-screen Diff opts in. Other DOM surfaces keep their own WebView.
  var shared: Bool = false
  private var sharedSourceLoaded = false
  private var ownsMessageHandler = false
  private var pendingScripts: [String] = []
  private var injectedObjectJson: String?
  private weak var scrollOwner: UIViewController?

  // MARK: - WKWebView / UIScrollView props (mutable post-creation)

  var webviewDebuggingEnabled: Bool = false {
    didSet {
      if #available(iOS 16.4, *) {
        webView?.isInspectable = webviewDebuggingEnabled
      }
    }
  }

  var decelerationRate: UIScrollView.DecelerationRate = .normal

  var bounces: Bool = true {
    didSet { webView?.scrollView.bounces = bounces }
  }
  var scrollEnabled: Bool = true {
    didSet { webView?.scrollView.isScrollEnabled = scrollEnabled }
  }
  var pagingEnabled: Bool = false {
    didSet { webView?.scrollView.isPagingEnabled = pagingEnabled }
  }
  var directionalLockEnabled: Bool = true {
    didSet { webView?.scrollView.isDirectionalLockEnabled = directionalLockEnabled }
  }
  var showsHorizontalScrollIndicator: Bool = true {
    didSet { webView?.scrollView.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator }
  }
  var showsVerticalScrollIndicator: Bool = true {
    didSet { webView?.scrollView.showsVerticalScrollIndicator = showsVerticalScrollIndicator }
  }
  var automaticallyAdjustsScrollIndicatorInsets: Bool = true {
    didSet {
      webView?.scrollView.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
    }
  }
  var contentInsetAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior = .automatic {
    didSet {
      // Preserve contentOffset so safe-area re-application doesn't jump the page.
      guard let scrollView = webView?.scrollView else { return }
      let contentOffset = scrollView.contentOffset
      scrollView.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
      scrollView.contentOffset = contentOffset
    }
  }

  // MARK: - Keyboard props

  // Hides the input accessory bar shown above the keyboard while a web text
  // field is focused. Mirrors `react-native-webview`'s `hideKeyboardAccessoryView`.
  var hideKeyboardAccessoryView: Bool = false {
    didSet { webView?.hidesInputAccessoryView = hideKeyboardAccessoryView }
  }

  // MARK: - RCTAutoInsetsProtocol storage

  @objc var contentInset: UIEdgeInsets = .zero {
    didSet { refreshContentInset() }
  }
  @objc var automaticallyAdjustContentInsets: Bool = true {
    didSet { refreshContentInset() }
  }

  internal typealias SyncCompletionHandler = (String?) -> Void

  private static let EVAL_PROMPT_HEADER = "__EXPO_DOM_WEBVIEW_JS_EVAL__"
  static let POST_MESSAGE_HANDLER_NAME = "ReactNativeWebView"

  private let onMessage = EventDispatcher()
  private let onContentProcessDidTerminate = EventDispatcher()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    super.backgroundColor = .clear
    self.id = DomWebViewRegistry.shared.add(webView: self)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    webView?.frame = bounds
    attachScrollOwner()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard shared else { return }
    if window != nil, webView == nil {
      reload()
    } else if window == nil, let webView {
      detachScrollOwner()
      SharedDiffWebView.shared.detach(webView, from: self)
      releaseSharedWebView(webView)
    } else {
      attachScrollOwner()
    }
  }

  override var backgroundColor: UIColor? {
    didSet { applyBackgroundColor() }
  }

  private func applyBackgroundColor() {
    let color = backgroundColor
    self.isOpaque = (color ?? UIColor.clear).cgColor.alpha == 1.0
    webView?.isOpaque = self.isOpaque
    webView?.scrollView.backgroundColor = color
    webView?.backgroundColor = color
  }

  deinit {
    if shared, let webView {
      if Thread.isMainThread {
        SharedDiffWebView.shared.detach(webView, from: self)
      } else {
        DispatchQueue.main.async { [weak webView] in
          guard let webView else { return }
          SharedDiffWebView.shared.detachOrphaned(webView)
        }
      }
    } else {
      webView?.uiDelegate = nil
      webView?.navigationDelegate = nil
      webView?.scrollView.delegate = nil
      webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }
    DomWebViewRegistry.shared.remove(webViewId: self.id)
  }

  // MARK: - Public methods

  func reload() {
    if webView == nil {
      setupWebView()
    }

    let scriptsChanged = needsResetupScripts
    if needsResetupScripts {
      resetupScripts()
      needsResetupScripts = false
    }

    if let source,
      let request = RCTConvert.nsurlRequest(source.toDictionary(appContext: appContext)),
      let requestURL = request.url,
      let webView,
      !SharedDiffWebView.urlsMatch(webView.url, requestURL)
        && !(shared && sharedSourceLoaded
          && SharedDiffWebView.shared.matches(webView, sourceURL: requestURL))
    {
      load(request: request)
    } else if scriptsChanged, webView?.url != nil {
      if shared {
        replaySharedProps()
      } else {
        // User scripts only run at .atDocumentStart; reload to pick up the new ones.
        webView?.reload()
      }
    }
  }

  func forceReload() {
    if webView?.url != nil {
      if shared, let webView {
        SharedDiffWebView.shared.willReload(webView)
      }
      webView?.reload()
      return
    }
    guard let source,
      let request = RCTConvert.nsurlRequest(source.toDictionary(appContext: appContext)) else {
      return
    }
    if webView == nil {
      setupWebView()
    }
    load(request: request)
  }

  private func load(request: URLRequest) {
    guard let url = request.url, SharedDiffWebView.isAllowedSource(url) else { return }
    if shared, let webView {
      sharedSourceLoaded = true
      SharedDiffWebView.shared.didStartLoading(webView, sourceURL: url)
    }
    if url.isFileURL {
      // Grant read access to the bundle so DOM components can load sibling assets.
      webView?.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    } else {
      webView?.load(request)
    }
  }

  func scrollTo(offset: CGPoint, animated: Bool) {
    webView?.scrollView.setContentOffset(offset, animated: animated)
  }

  func injectJavaScript(_ script: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.webView != nil {
        self.webView?.evaluateJavaScript(script)
      } else {
        self.pendingScripts.append(script)
      }
    }
  }

  func setSource(_ source: DomWebViewSource) {
    self.source = source
  }

  func setInjectedJS(_ script: String?) {
    if let script, !script.isEmpty {
      injectedJS = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    } else {
      injectedJS = nil
    }
    needsResetupScripts = true
  }

  func setInjectedJSBeforeContentLoaded(_ script: String?) {
    if let script, !script.isEmpty {
      injectedJSBeforeContentLoaded = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    } else {
      injectedJSBeforeContentLoaded = nil
    }
    needsResetupScripts = true
  }

  func setInjectedJavaScriptObject(_ source: String?) {
    injectedObjectJson = source
    if let source, !source.isEmpty {
      let script = """
      window.ReactNativeWebView = window.ReactNativeWebView || {};
      window.ReactNativeWebView.injectedObjectJson = function () {
        return JSON.stringify(\(source));
      }
      true;
      """
      injectedObjectJsonScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    } else {
      injectedObjectJsonScript = nil
    }
    needsResetupScripts = true
  }

  // MARK: - UIScrollViewDelegate implementations

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    scrollView.decelerationRate = decelerationRate
  }

  // MARK: - WKUIDelegate implementations

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping SyncCompletionHandler
  ) {
    if !prompt.hasPrefix(Self.EVAL_PROMPT_HEADER) || !useExpoModulesBridge {
      completionHandler(nil)
      return
    }
    let script = String(prompt.dropFirst(Self.EVAL_PROMPT_HEADER.count))
    if let data = script.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
      let deferredId = json["deferredId"] as? Int,
      let source = json["source"] as? String {
      nativeJsiEvalSync(deferredId: deferredId, source: source, completionHandler: completionHandler)
    } else {
      completionHandler("Invalid parameters for nativeJsiEvalSync")
    }
  }

  // MARK: - RCTAutoInsetsProtocol implementations

  @objc func refreshContentInset() {
    guard let webView else { return }
    RCTView.autoAdjustInsets(for: self, with: webView.scrollView, updateOffset: true)
  }

  // MARK: - WKNavigationDelegate implementations

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url, SharedDiffWebView.isAllowedSource(url) else {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log.warn("WebView content process terminated")
    if shared {
      SharedDiffWebView.shared.didTerminate(webView)
    }
    onContentProcessDidTerminate(createBaseEventPayload())
  }

  // MARK: - WKScriptMessageHandler implementations

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name == Self.POST_MESSAGE_HANDLER_NAME {
      if shared, message.frameInfo.isMainFrame, let body = message.body as? String {
        SharedDiffWebView.dispatchBridgeMessage(body, from: message.webView)
      }
      var payload = createBaseEventPayload()
      payload["data"] = message.body
      onMessage(payload)
      return
    }
  }

  // MARK: - Internals

  func releaseSharedWebView(_ sharedWebView: DomWKWebView) {
    guard webView === sharedWebView else { return }
    detachScrollOwner()
    webView = nil
    sharedSourceLoaded = false
    ownsMessageHandler = false
  }

  private func setupWebView() {
    let sharedSourceURL = shared
      ? source.flatMap { RCTConvert.nsurlRequest($0.toDictionary(appContext: appContext))?.url }
      : nil
    let retained = sharedSourceURL.flatMap {
      SharedDiffWebView.shared.take(for: self, sourceURL: $0)
    }
    if retained == nil, shared, SharedDiffWebView.shared.hasInstance {
      return
    }

    let webView: DomWKWebView
    if let retained {
      webView = retained.webView
      webView.frame = bounds
    } else {
      let config = shared ? SharedDiffWebView.makeSharedConfiguration() : WKWebViewConfiguration()
      if !shared {
        config.userContentController = WKUserContentController()
      }
      config.allowsInlineMediaPlayback = allowsInlineMediaPlayback
      config.allowsPictureInPictureMediaPlayback = allowsPictureInPictureMediaPlayback
      config.allowsAirPlayForMediaPlayback = allowsAirPlayForMediaPlayback
      config.mediaTypesRequiringUserActionForPlayback = mediaPlaybackRequiresUserAction ? .all : []
      webView = DomWKWebView(frame: bounds, configuration: config)
      if let sharedSourceURL {
        SharedDiffWebView.shared.keep(webView, for: self, sourceURL: sharedSourceURL)
      }
    }
    webView.hidesInputAccessoryView = hideKeyboardAccessoryView
    webView.uiDelegate = self
    webView.navigationDelegate = self

    let scrollView = webView.scrollView
    scrollView.delegate = self
    scrollView.bounces = bounces
    scrollView.isScrollEnabled = scrollEnabled
    scrollView.isPagingEnabled = pagingEnabled
    scrollView.isDirectionalLockEnabled = directionalLockEnabled
    scrollView.showsHorizontalScrollIndicator = showsHorizontalScrollIndicator
    scrollView.showsVerticalScrollIndicator = showsVerticalScrollIndicator
    scrollView.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
    scrollView.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior

    if #available(iOS 16.4, *) {
      webView.isInspectable = webviewDebuggingEnabled
    }

    self.webView = webView
    sharedSourceLoaded = retained != nil
    ownsMessageHandler = false
    addSubview(webView)

    applyBackgroundColor()
    refreshContentInset()
    resetupScripts()
    needsResetupScripts = false
    attachScrollOwner()
    flushPendingScripts()

    guard retained?.ready == true else { return }
    DispatchQueue.main.async { [weak self, weak webView] in
      guard let self, let webView, self.webView === webView else { return }
      self.replaySharedProps()
    }
  }

  private func flushPendingScripts() {
    let scripts = pendingScripts
    pendingScripts.removeAll()
    for script in scripts {
      webView?.evaluateJavaScript(script)
    }
  }

  private func replaySharedProps() {
    guard let source = injectedObjectJson, !source.isEmpty else {
      SharedDiffWebView.shared.attachDiff()
      return
    }
    let script = """
    (function() {
      var obj = \(source);
      var initial = obj && obj.initialProps;
      if (initial) {
        window.dispatchEvent(new CustomEvent("$$dom_event", { detail: { type: "$$props", data: initial } }));
        var props = initial.props || {};
        if (window.__lodyAttachDiff) {
          window.__lodyAttachDiff({
            path: props.path || "",
            oldText: props.oldText || "",
            newText: props.newText || "",
            diffStyle: props.diffStyle || "unified",
            theme: props.theme || "light"
          });
        }
      } else if (window.__lodyAttachDiff) {
        window.__lodyAttachDiff();
      }
      true;
    })();
    """
    webView?.evaluateJavaScript(script)
  }

  private func attachScrollOwner() {
    guard scrollEnabled, window != nil, let webView else { return }
    var responder = next
    while let current = responder {
      if let owner = current as? UIViewController {
        owner.setContentScrollView(webView.scrollView, for: .top)
        owner.setContentScrollView(webView.scrollView, for: .bottom)
        scrollOwner = owner
        return
      }
      responder = current.next
    }
  }

  private func detachScrollOwner() {
    guard let owner = scrollOwner, let webView else {
      scrollOwner = nil
      return
    }
    if owner.contentScrollView(for: .top) === webView.scrollView {
      owner.setContentScrollView(nil, for: .top)
      owner.setContentScrollView(nil, for: .bottom)
    }
    scrollOwner = nil
  }

  private func createBaseEventPayload() -> [String: Any] {
    return [
      "url": webView?.url?.absoluteString ?? "",
      "title": webView?.title ?? ""
    ]
  }

  private func resetupScripts() {
    guard let userContentController = webView?.configuration.userContentController else {
      return
    }
    userContentController.removeAllUserScripts()
    if !ownsMessageHandler {
      userContentController.removeAllScriptMessageHandlers()
      userContentController.add(WeakScriptMessageHandler(delegate: self), name: Self.POST_MESSAGE_HANDLER_NAME)
      ownsMessageHandler = true
    }

    if let injectedJS {
      userContentController.addUserScript(injectedJS)
    }
    if let injectedJSBeforeContentLoaded {
      userContentController.addUserScript(injectedJSBeforeContentLoaded)
    }
    if let injectedObjectJsonScript {
      userContentController.addUserScript(injectedObjectJsonScript)
    }

    let addRNWObjectScript = """
    window.ReactNativeWebView ||= {};
    window.ReactNativeWebView.postMessage = function postMessage(data) {
      window.webkit.messageHandlers.\(Self.POST_MESSAGE_HANDLER_NAME).postMessage(String(data));
    };
    true;
    """
    userContentController.addUserScript(WKUserScript(source: addRNWObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

    if useExpoModulesBridge {
      let addDomWebViewBridgeScript = """
      window.ExpoDomWebViewBridge = {
        eval: function eval(params) {
          return window.prompt('\(Self.EVAL_PROMPT_HEADER)' + params);
        },
      };
      true;
      """
      userContentController.addUserScript(WKUserScript(source: addDomWebViewBridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

      guard let webViewId = self.id else {
        return
      }

      let addExpoDomWebViewObjectScript = "\(INSTALL_GLOBALS_SCRIPT);true;"
        .replacingOccurrences(of: "\"%%WEBVIEW_ID%%\"", with: String(webViewId))
      userContentController.addUserScript(WKUserScript(source: addExpoDomWebViewObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }
  }

  private func nativeJsiEvalSync(deferredId: Int, source: String, completionHandler: @escaping SyncCompletionHandler) {
    guard let appContext else {
      completionHandler("Missing AppContext")
      return
    }
    guard let webViewId = self.id else {
      completionHandler("Missing webViewId")
      return
    }
    guard let runtime = try? appContext.runtime else {
      completionHandler("Missing JS Runtime")
      return
    }
    try? appContext.runtime.schedule {
      let wrappedSource = NATIVE_EVAL_WRAPPER_SCRIPT
        .replacingOccurrences(of: "\"%%DEFERRED_ID%%\"", with: String(deferredId))
        .replacingOccurrences(of: "\"%%WEBVIEW_ID%%\"", with: String(webViewId))
        .replacingOccurrences(of: "\"%%SOURCE%%\"", with: source)
      do {
        let result = try runtime.eval(wrappedSource)
        completionHandler(result.getString())
      } catch {
        completionHandler("\(error)")
      }
    }
  }
}
