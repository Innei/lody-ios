import ExpoModulesCore
import OneSignalFramework
import UserNotifications
import UIKit

/// Process-owned listener: notification clicks can precede the React bridge.
final class PushNotifications: NSObject, OSNotificationClickListener, OSNotificationLifecycleListener, OSPushSubscriptionObserver {
  static let shared = PushNotifications()
  private(set) var configured = false
  private var userId: String?
  private var clicks = PushClickBuffer()
  var onClickAvailable: (() -> Void)?
  var visibleRoute = ""
  private var registered = false
  #if DEBUG
  private var verificationShown = false
  var onRegistered: (() -> Void)?
  #endif

  func start(_ options: [UIApplication.LaunchOptionsKey: Any]?) {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--ui-verify") || ProcessInfo.processInfo.arguments.contains("--lody-offline") { return }
    #endif
    guard !configured, let appId = Bundle.main.object(forInfoDictionaryKey: "LodyOneSignalAppId") as? String,
          UUID(uuidString: appId) != nil else { return }
    configured = true
    OneSignal.Debug.setLogLevel(.LL_NONE)
    OneSignal.initialize(appId, withLaunchOptions: options)
    OneSignal.User.pushSubscription.addObserver(self)
    evaluateSubscription(OneSignal.User.pushSubscription.id)
    OneSignal.Notifications.addClickListener(self)
    OneSignal.Notifications.addForegroundLifecycleListener(self)
  }

  func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
    DispatchQueue.main.async { self.evaluateSubscription(state.current.id) }
  }

  private func evaluateSubscription(_ id: String?) {
    registered = PushClickBuffer.isRegistered(id)
    #if DEBUG
    if registered { onRegistered?() }
    #endif
  }

  #if DEBUG
  func verify(from controller: UIViewController) {
    guard configured, registered, !verificationShown, controller.presentedViewController == nil, controller.viewIfLoaded?.window != nil else { return }
    verificationShown = true
    let alert = UIAlertController(title: "Your OneSignal SDK integration is complete!", message: "You can now send Push Notifications & In-App Messages through OneSignal. Tap below to enable push notifications.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Got it", style: .default) { _ in
      OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
    })
    controller.present(alert, animated: true)
  }
  #endif

  func identify(_ id: String?) {
    guard configured else { return }
    let previous = userId ?? OneSignal.User.externalId
    userId = id
    clicks.identify(id)
    if let id, !id.isEmpty {
      if let previous, previous != id { clearDelivered() }
      OneSignal.login(id)
      // Never trigger the system permission prompt as a side effect of login.
      if OneSignal.Notifications.permission { OneSignal.User.pushSubscription.optIn() }
    } else {
      visibleRoute = ""
      if previous != nil { OneSignal.logout() }
      OneSignal.User.pushSubscription.optOut()
      clearDelivered()
    }
  }

  func status(_ completion: @escaping ([String: Any]) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        let permission: String
        switch settings.authorizationStatus {
        case .notDetermined: permission = "notDetermined"
        case .denied: permission = "denied"
        case .authorized, .provisional, .ephemeral: permission = "authorized"
        @unknown default: permission = "denied"
        }
        if self.configured, self.userId != nil, permission == "authorized" {
          OneSignal.User.pushSubscription.optIn()
        }
        completion(["configured": self.configured, "permission": permission, "registered": self.registered])
      }
    }
  }

  func request(_ completion: @escaping (Bool) -> Void) {
    guard configured, let requestedUser = userId else { completion(false); return }
    OneSignal.Notifications.requestPermission({ accepted in
      DispatchQueue.main.async {
        if accepted, self.userId == requestedUser { OneSignal.User.pushSubscription.optIn() }
        completion(accepted)
      }
    }, fallbackToSettings: false)
  }

  func readPending() -> [String: String]? { clicks.pending }
  func acknowledge(_ id: String) { clicks.acknowledge(id) }

  func onClick(event: OSNotificationClickEvent) {
    DispatchQueue.main.async {
      guard let id = event.notification.notificationId,
            let route = event.notification.additionalData?["route"] as? String,
            route.utf8.count <= 2048,
            let owner = (event.notification.additionalData?["recipientUserId"] as? String) ?? self.userId ?? OneSignal.User.externalId, !owner.isEmpty else { return }
      self.clicks.receive(id: id, route: route, userId: owner)
      self.onClickAvailable?()
    }
  }

  func onWillDisplay(event: OSNotificationWillDisplayEvent) {
    event.preventDefault()
    DispatchQueue.main.async {
      let route = event.notification.additionalData?["route"] as? String
      let recipient = event.notification.additionalData?["recipientUserId"] as? String
      guard self.userId != nil,
            recipient == nil || recipient == self.userId,
            self.visibleRoute.isEmpty || route != self.visibleRoute else { return }
      event.notification.display()
    }
  }

  private func clearDelivered() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().setBadgeCount(0)
  }
}

public final class PushAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func applicationDidBecomeActive(_ application: UIApplication) {
    PushNotifications.shared.status { _ in }
  }

  public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    PushNotifications.shared.start(launchOptions)
    return true
  }
}
