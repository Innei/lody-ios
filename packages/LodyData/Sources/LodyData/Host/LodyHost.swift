import Foundation

@MainActor
public protocol LodyHost: AnyObject {
  var isActive: Bool { get }
  var isBackground: Bool { get }
  func open(_ url: URL) async -> Bool
  func copyLink(_ url: URL)
  func beginSendAllowance(expired: @escaping @MainActor () -> Void) -> AnyObject?
  func endSendAllowance(_ token: AnyObject)
  func toast(_ message: String, kind: String)
  func alert(title: String, message: String)
  func presentAuthorization(_ url: URL) -> Bool
  func dismissAuthorization()
  func catalogDidUpdate(_ catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String)
  func clearSharedData()
  func forgetDevice()
}

@MainActor
public enum LodyHosting {
  public static var current: LodyHost?
}

extension Notification.Name {
  // Hosts translate their platform lifecycle into these; the runtime never reads UIApplication or NSApplication.
  public static let lodyHostDidEnterBackground = Notification.Name("LodyHostDidEnterBackground")
  public static let lodyHostDidBecomeActive = Notification.Name("LodyHostDidBecomeActive")
  public static let lodyHostDidReceiveMemoryWarning = Notification.Name("LodyHostDidReceiveMemoryWarning")
}
