import UserNotifications
import OneSignalExtension

final class NotificationService: UNNotificationServiceExtension {
  private var handler: ((UNNotificationContent) -> Void)?
  private var request: UNNotificationRequest?
  private var content: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.request = request
    handler = contentHandler
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    self.content = content
    OneSignalExtension.didReceiveNotificationExtensionRequest(request, with: content, withContentHandler: contentHandler)
  }

  override func serviceExtensionTimeWillExpire() {
    guard let request, let content, let handler else { return }
    OneSignalExtension.serviceExtensionTimeWillExpireRequest(request, with: content)
    handler(content)
  }
}
