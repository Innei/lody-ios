import ExpoModulesCore
import UIKit
import WebKit
import YiTong

final class LodyDiffView: ExpoView {
  let onRender = EventDispatcher()
  let onFail = EventDispatcher()
  private var controller: DiffViewController?
  private weak var scrollOwner: UIViewController?
  private var contentObservation: NSKeyValueObservation?
  private var path = ""
  private var oldText: String?
  private var newText: String?
  private var handle = ""
  private var style = "unified"
  private var scrollEnabled = true
  private var renderScheduled = false
  private var lastHeight: CGFloat = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    backgroundColor = .clear
  }

  func setPath(_ value: String) { path = value; scheduleRender() }
  func setOldText(_ value: String?) { oldText = value; scheduleRender() }
  func setNewText(_ value: String?) { newText = value; scheduleRender() }
  func setHandle(_ value: String) { handle = value; scheduleRender() }
  func setStyle(_ value: String) { style = value; scheduleRender() }
  func setScrollEnabled(_ value: Bool) {
    scrollEnabled = value
    webView?.scrollView.isScrollEnabled = value
  }

  private var webView: WKWebView? {
    controller?.view.subviews.compactMap { $0 as? WKWebView }.first
  }

  // Props arrive one setter at a time; render once per run loop turn.
  private func scheduleRender() {
    guard !renderScheduled else { return }
    renderScheduled = true
    DispatchQueue.main.async { [weak self] in
      self?.renderScheduled = false
      self?.render()
    }
  }

  private func document() -> DiffDocument? {
    if !handle.isEmpty {
      guard let content = ContentStore.shared.get(handle) else { return nil }
      if content.kind == "diff" {
        let sides = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: String] ?? [:]
        return DiffDocument(
          files: [DiffFile(oldPath: path, newPath: path, oldContents: sides["old"] ?? "", newContents: sides["new"] ?? "")],
          title: path
        )
      }
      return nil
    }
    guard oldText != nil || newText != nil else { return nil }
    return DiffDocument(
      files: [DiffFile(oldPath: path, newPath: path, oldContents: oldText ?? "", newContents: newText ?? "")],
      title: path
    )
  }

  private func configuration() -> DiffConfiguration {
    DiffConfiguration(
      appearance: .automatic,
      style: style == "split" ? .split : .unified,
      indicators: .bars,
      showsLineNumbers: true,
      showsChangeBackgrounds: true,
      wrapsLines: false,
      showsFileHeaders: false,
      inlineChangeStyle: .wordAlt,
      allowsSelection: true,
      fontScale: UIFont.dynamicScale(compatibleWith: traitCollection),
      isEmbedded: true
    )
  }

  private func render() {
    guard let document = document() else {
      if !handle.isEmpty { onFail(["message": "content_expired"]) }
      return
    }
    if let controller {
      controller.update(document: document, configuration: configuration())
      return
    }
    let controller = DiffViewController(document: document, configuration: configuration()) { [weak self] event in
      self?.handle(event)
    }
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = .clear
    controller.view.frame = bounds
    addSubview(controller.view)
    self.controller = controller
    if let webView {
      webView.scrollView.isScrollEnabled = scrollEnabled
      webView.scrollView.contentInsetAdjustmentBehavior = scrollEnabled ? .automatic : .never
      DiffWebTypography.pin(webView)
      contentObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
        self?.reportHeight(scrollView.contentSize.height)
        self?.restToTop()
      }
    }
    attachScrollOwner()
  }

  // The navigation bar's soft scroll edge only follows a registered scroll view.
  private func attachScrollOwner() {
    guard scrollEnabled, window != nil, scrollOwner == nil, let webView else { return }
    var responder = next
    while let current = responder {
      if let owner = current as? UIViewController {
        if let controller, controller.parent == nil {
          owner.addChild(controller)
          addSubview(controller.view)
          controller.didMove(toParent: owner)
        }
        owner.setContentScrollView(webView.scrollView, for: .top)
        owner.setContentScrollView(webView.scrollView, for: .bottom)
        scrollOwner = owner
        restToTop()
        return
      }
      responder = current.next
    }
  }

  // The header inset arrives after the page loaded at offset 0; snap an
  // untouched scroll view under the bar instead of leaving the first lines hidden.
  private func restToTop() {
    guard let scrollView = webView?.scrollView else { return }
    let top = -scrollView.adjustedContentInset.top
    if scrollView.contentOffset.y > top, scrollView.contentOffset.y <= 0 {
      scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: top)
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    restToTop()
  }

  private func handle(_ event: DiffEvent) {
    switch event {
    case .didRender(let summary):
      if let webView { DiffWebTypography.pin(webView) }
      onRender(["fileCount": summary.fileCount, "contentHeight": Double(webView?.scrollView.contentSize.height ?? 0)])
    case .didFail(let error):
      onFail(["message": error.message])
    default:
      break
    }
  }

  private func reportHeight(_ height: CGFloat) {
    guard abs(height - lastHeight) > 0.5 else { return }
    lastHeight = height
    onRender(["fileCount": 1, "contentHeight": Double(height)])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    controller?.view.frame = bounds
    attachScrollOwner()
    restToTop()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attachScrollOwner()
  }

  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    guard newWindow == nil, let owner = scrollOwner else { return }
    if owner.contentScrollView(for: .top) === webView?.scrollView {
      owner.setContentScrollView(nil, for: .top)
      owner.setContentScrollView(nil, for: .bottom)
    }
    scrollOwner = nil
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil, let controller, controller.parent != nil {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
    }
    super.willMove(toSuperview: newSuperview)
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
        || previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
      scheduleRender()
    }
  }
}
