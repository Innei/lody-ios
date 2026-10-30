import AppKit
import LodyData

@MainActor
struct MacEnvironment {
  var sessions: MacSessionsSource
  var pane: @MainActor (_ sessionId: String) -> MacSessionPane
  var newSession: @MainActor () -> NSViewController
  var requiresAccount = true
  var windowIdentifier = "main"
  var titlePrefix = ""
  var windowClass: NSWindow.Type = NSWindow.self
  var account: @MainActor () -> AuthAccount? = { AuthSession.shared.snapshot.account }
  var authChanges: Notification.Name = .lodyAuthDidChange
  var signIn: @MainActor () -> SignInViewController = { SignInViewController() }

  static var live: MacEnvironment {
    MacEnvironment(
      sessions: .live,
      pane: { SessionControllerFactory.make(sessionId: $0) },
      newSession: { MacNewSessionController(source: .live, service: .live) }
    )
  }
}
