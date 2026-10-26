import ExpoModulesCore
import UIKit

// Temporary bridge while the home root is still a React page: it only hosts the
// native inbox. Delete it once the root page goes native.
final class LodyInboxView: ExpoView {
  private let inbox = InboxController()
  private weak var host: UIViewController?
  private var observer: NSObjectProtocol?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    observer = NotificationCenter.default.addObserver(
      forName: LodyScrollEdges.ownerChanged, object: inbox, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.forwardScrollEdges() }
    }
  }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if inbox.isViewLoaded { inbox.view.frame = bounds }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, host == nil else { return }
    var responder = next
    while let current = responder, !(current is UIViewController) { responder = current.next }
    guard let controller = responder as? UIViewController else { return }
    host = controller
    controller.addChild(inbox)
    inbox.view.frame = bounds
    addSubview(inbox.view)
    inbox.didMove(toParent: controller)
    forwardScrollEdges()
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil, let host {
      if let scroll = inbox.contentScrollView(for: .top) { LodyScrollEdges.unbind(scroll, from: host) }
      inbox.willMove(toParent: nil)
      inbox.view.removeFromSuperview()
      inbox.removeFromParent()
      self.host = nil
    }
    super.willMove(toSuperview: newSuperview)
  }

  private func forwardScrollEdges() {
    guard let host, let scroll = inbox.contentScrollView(for: .top) else { return }
    LodyScrollEdges.bind(scroll, to: host)
  }
}
