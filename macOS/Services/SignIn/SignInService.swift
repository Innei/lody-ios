import AppKit
import LodyData

@MainActor
struct SignInService {
  var snapshot: () -> AuthSnapshot
  var login: () async throws -> Void
  var cancel: () -> Void
  var reopen: () -> Void
  var changes: Notification.Name = .lodyAuthDidChange
  var copy: (String) -> Void = { text in
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  static let live = SignInService(
    snapshot: { AuthSession.shared.snapshot },
    login: { try await AuthSession.shared.login() },
    cancel: { AuthSession.shared.cancel() },
    reopen: { AuthSession.shared.reopen() }
  )
}
