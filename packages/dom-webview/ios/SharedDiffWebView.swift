import UIKit
import WebKit

/// Single Diff-only WKWebView. Warmer and FileDiff take turns owning it;
/// a foreground host cannot be stolen by the offscreen warmer.
final class SharedDiffWebView: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  static let shared = SharedDiffWebView()

  private(set) var instanceId = ""
  private(set) var navigationCount = 0
  private weak var owner: DomWebView?
  private var webView: DomWKWebView?
  private var sourceURL: URL?
  private var ready = false
  private let parkingHost = UIView()
  private var parkingHandler: WeakScriptMessageHandler?
  private var memoryObserver: NSObjectProtocol?

  override init() {
    super.init()
    memoryObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.discardIfParked()
    }
  }

  var hasInstance: Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    return webView != nil
  }

  func probe() -> [String: Any] {
    dispatchPrecondition(condition: .onQueue(.main))
    return [
      "instanceId": instanceId,
      "navigationCount": navigationCount,
      "parked": owner == nil && webView != nil,
    ]
  }

  func take(for owner: DomWebView, sourceURL: URL) -> (webView: DomWKWebView, ready: Bool)? {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let webView else { return nil }
    guard Self.urlsMatch(self.sourceURL, sourceURL) else {
      discard()
      return nil
    }
    if let previous = self.owner, previous !== owner {
      if Self.isForegroundHost(previous), !Self.isForegroundHost(owner) {
        return nil
      }
      previous.releaseSharedWebView(webView)
    }
    self.owner = owner
    webView.removeFromSuperview()
    parkingHost.removeFromSuperview()
    webView.navigationDelegate = owner
    applyProbe(webView)
    return (webView, ready)
  }

  func keep(_ webView: DomWKWebView, for owner: DomWebView, sourceURL: URL) {
    dispatchPrecondition(condition: .onQueue(.main))
    discard()
    self.webView = webView
    self.owner = owner
    self.sourceURL = sourceURL
    ready = false
    instanceId = UUID().uuidString
    navigationCount = 0
    applyProbe(webView)
  }

  func detach(_ webView: DomWKWebView, from owner: DomWebView) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard self.webView === webView, self.owner === owner else { return }
    self.owner = nil
    park(webView)
  }

  func detachOrphaned(_ webView: DomWKWebView) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard self.webView === webView, owner == nil else { return }
    park(webView)
  }

  func matches(_ webView: DomWKWebView, sourceURL: URL) -> Bool {
    self.webView === webView && Self.urlsMatch(self.sourceURL, sourceURL)
  }

  func didStartLoading(_ webView: DomWKWebView, sourceURL: URL) {
    guard self.webView === webView else { return }
    self.sourceURL = sourceURL
    ready = false
    navigationCount += 1
  }

  func willReload(_ webView: WKWebView) {
    guard self.webView === webView else { return }
    ready = false
    navigationCount += 1
  }

  func didBecomeReady(_ webView: WKWebView) {
    guard self.webView === webView else { return }
    ready = true
  }

  func didTerminate(_ webView: WKWebView) {
    guard self.webView === webView else { return }
    ready = false
    if owner == nil {
      discard()
    }
  }

  func reset() {
    dispatchPrecondition(condition: .onQueue(.main))
    discard()
  }

  func resetDiff() {
    dispatchPrecondition(condition: .onQueue(.main))
    webView?.evaluateJavaScript("window.__lodyResetDiff?.(); true;")
  }

  func attachDiff() {
    dispatchPrecondition(condition: .onQueue(.main))
    webView?.evaluateJavaScript("window.__lodyAttachDiff?.(); true;")
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    didTerminate(webView)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url, Self.isAllowedSource(url) else {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == DomWebView.POST_MESSAGE_HANDLER_NAME,
      let body = message.body as? String
    else { return }
    Self.dispatchBridgeMessage(body, from: message.webView)
  }

  static func dispatchBridgeMessage(_ body: String, from webView: WKWebView?) {
    guard let data = body.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = json["type"] as? String
    else { return }
    if type == "$$dom_ready" || type == "lody:diff-runtime-ready", let webView {
      shared.didBecomeReady(webView)
    }
  }

  static func urlsMatch(_ lhs: URL?, _ rhs: URL) -> Bool {
    guard let lhs else { return false }
    if lhs.absoluteURL == rhs.absoluteURL { return true }
    guard lhs.isFileURL, rhs.isFileURL else { return false }
    return lhs.standardizedFileURL.resolvingSymlinksInPath().path
      == rhs.standardizedFileURL.resolvingSymlinksInPath().path
  }

  static func isAllowedSource(_ url: URL) -> Bool {
    if url.isFileURL {
      let path = url.standardizedFileURL.path
      let home = NSHomeDirectory()
      return path.hasPrefix(home) || path.contains(".app/")
    }
    #if DEBUG
    guard let host = url.host?.lowercased() else { return false }
    return ["localhost", "127.0.0.1", "0.0.0.0"].contains(host)
      && (url.scheme == "http" || url.scheme == "https")
    #else
    return false
    #endif
  }

  static func makeSharedConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.userContentController = WKUserContentController()
    return config
  }

  private func park(_ webView: DomWKWebView) {
    webView.uiDelegate = nil
    webView.navigationDelegate = self
    webView.scrollView.delegate = nil
    webView.scrollView.isScrollEnabled = false
    bindParkingHandler(webView)
    resetDiff()
    layoutParked(webView)
  }

  private func layoutParked(_ parked: DomWKWebView? = nil) {
    guard let webView = parked ?? (owner == nil ? webView : nil) else { return }
    let size = Self.viewportSize()
    parkingHost.frame = CGRect(x: -size.width, y: 0, width: size.width, height: size.height)
    parkingHost.isUserInteractionEnabled = false
    webView.frame = parkingHost.bounds
    if webView.superview !== parkingHost {
      parkingHost.addSubview(webView)
    }
    if parkingHost.superview == nil, let window = Self.keyWindow() {
      window.insertSubview(parkingHost, at: 0)
    }
    parkingHost.layoutIfNeeded()
  }

  private func bindParkingHandler(_ webView: DomWKWebView) {
    let userContentController = webView.configuration.userContentController
    userContentController.removeAllScriptMessageHandlers()
    let handler = WeakScriptMessageHandler(delegate: self)
    parkingHandler = handler
    userContentController.add(handler, name: DomWebView.POST_MESSAGE_HANDLER_NAME)
  }

  private func discardIfParked() {
    dispatchPrecondition(condition: .onQueue(.main))
    if owner == nil { discard() }
  }

  private func discard() {
    if let webView {
      owner?.releaseSharedWebView(webView)
      webView.stopLoading()
      webView.removeFromSuperview()
      webView.uiDelegate = nil
      webView.navigationDelegate = nil
      webView.scrollView.delegate = nil
      webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
    parkingHost.removeFromSuperview()
    parkingHandler = nil
    owner = nil
    webView = nil
    sourceURL = nil
    ready = false
    instanceId = ""
    navigationCount = 0
  }

  private func applyProbe(_ webView: DomWKWebView) {
    #if DEBUG
    webView.accessibilityIdentifier = "diff-webview-probe"
    webView.accessibilityLabel = "\(instanceId) \(navigationCount)"
    webView.isAccessibilityElement = true
    #endif
  }

  private static func isForegroundHost(_ view: UIView) -> Bool {
    guard let window = view.window, view.alpha > 0.01, !view.isHidden else { return false }
    let frame = view.convert(view.bounds, to: window)
    return frame.minX >= -1 && frame.maxX > 8 && frame.width > 8 && frame.height > 8
  }

  private static func viewportSize() -> CGSize {
    if let window = keyWindow() { return window.bounds.size }
    return UIScreen.main.bounds.size
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first
  }
}
