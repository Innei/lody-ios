import AppKit
import LodyData
import UserNotifications

@MainActor
final class MacNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = MacNotifier()
  static let key = "lody.mac.notifications"
  private var previous: SessionCatalog?
  private var workspaceId = ""
  private var observer: NSObjectProtocol?
  var onOpen: ((String) -> Void)?

  var enabled: Bool { UserDefaults.standard.bool(forKey: Self.key) }

  func start() {
    UNUserNotificationCenter.current().delegate = self
    observer = NotificationCenter.default.addObserver(forName: .lodyCatalogDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.catalogChanged() }
    }
    catalogChanged()
  }

  func setEnabled(_ on: Bool) async -> Bool {
    var granted = false
    if on { granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false }
    UserDefaults.standard.set(granted, forKey: Self.key)
    return granted
  }

  private func catalogChanged() {
    let state = SessionPublished.state()
    guard state.workspaceId == workspaceId else {
      workspaceId = state.workspaceId
      previous = state.catalog
      return
    }
    let onScreen = NSApp.isActive ? MacTabCoordinator.shared.streamingSession : nil
    let decisions = MacNotificationDecider.decide(previous: previous, next: state.catalog, onScreen: onScreen)
    previous = state.catalog
    guard enabled else { return }
    decisions.forEach(post)
  }

  private func post(_ decision: MacNotificationDecision) {
    let content = UNMutableNotificationContent()
    let sessionId: String
    switch decision {
    case let .permission(id, title):
      sessionId = id
      content.title = String(localized: "mac.notify.permission", bundle: .lodyMac)
      content.body = title
    case let .finished(id, title):
      sessionId = id
      content.title = String(localized: "mac.notify.finished", bundle: .lodyMac)
      content.body = title
    }
    content.sound = .default
    content.threadIdentifier = sessionId
    content.userInfo = ["sessionId": sessionId, "workspaceId": workspaceId]
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo
    guard let sessionId = info["sessionId"] as? String, let workspace = info["workspaceId"] as? String else { return }
    await MainActor.run {
      guard workspace == SessionPublished.state().workspaceId else { return }
      onOpen?(sessionId)
    }
  }
}
