import SafariServices
import UIKit

@MainActor
final class LodyUIKitHost: LodyHost {
  static let shared = LodyUIKitHost()

  var presenter: () -> UIViewController? = { LodyShell.shared.presenter }
  private var observers: [NSObjectProtocol] = []
  private var browser: SFSafariViewController?
  private var alertWindows: [UIWindow] = []

  private init() {
    let forwards: [(Notification.Name, Notification.Name)] = [
      (UIApplication.didEnterBackgroundNotification, .lodyHostDidEnterBackground),
      (UIApplication.didReceiveMemoryWarningNotification, .lodyHostDidReceiveMemoryWarning),
      (UIApplication.didBecomeActiveNotification, .lodyHostDidBecomeActive),
    ]
    for (source, target) in forwards {
      observers.append(NotificationCenter.default.addObserver(forName: source, object: nil, queue: .main) { _ in
        NotificationCenter.default.post(name: target, object: nil)
      })
    }
  }

  var isActive: Bool { UIApplication.shared.applicationState == .active }
  var isBackground: Bool { UIApplication.shared.applicationState == .background }

  func open(_ url: URL) async -> Bool {
    await UIApplication.shared.open(url)
  }

  func copyLink(_ url: URL) {
    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: url.absoluteString]], options: [.localOnly: true])
  }

  func beginSendAllowance(expired: @escaping @MainActor () -> Void) -> AnyObject? {
    let task = UIApplication.shared.beginBackgroundTask(withName: "Session send") {
      MainActor.assumeIsolated { expired() }
    }
    return task == .invalid ? nil : NSNumber(value: task.rawValue)
  }

  func endSendAllowance(_ token: AnyObject) {
    guard let number = token as? NSNumber else { return }
    UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: number.intValue))
  }

  func toast(_ message: String, kind: String) {
    LodyToastOverlay.shared.show(message: message, kind: kind)
  }

  func alert(title: String, message: String) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = presenter()?.view.window?.windowScene ?? scenes.first(where: { $0.activationState == .foregroundActive })
    else { return }
    let previous = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert
    window.backgroundColor = .clear
    window.rootViewController = UIViewController()
    window.rootViewController?.view.backgroundColor = .clear
    alertWindows.append(window)
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: String(localized: "common.ok", bundle: .lody), style: .default) { [weak self, weak window, weak previous] _ in
      window?.isHidden = true
      self?.alertWindows.removeAll { $0 === window }
      previous?.makeKey()
    })
    window.makeKeyAndVisible()
    window.rootViewController?.present(alert, animated: true)
  }

  func presentAuthorization(_ url: URL) -> Bool {
    guard let controller = presenter() else { return false }
    let browser = SFSafariViewController(url: url)
    self.browser = browser
    controller.present(browser, animated: true)
    return true
  }

  func dismissAuthorization() {
    browser?.dismiss(animated: true)
    browser = nil
  }

  func catalogDidUpdate(_ catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {
    LiveActivities.shared.sync(catalogJSON: catalogJSON, workspaceId: workspaceId, workspaceSlug: workspaceSlug,
      workspaceName: workspaceName, userId: userId)
  }

  func clearSharedData() {
    ShareStore.clear()
  }

  func forgetDevice() {
    PushNotifications.shared.identify(nil)
    LiveActivities.shared.endAll()
  }
}
