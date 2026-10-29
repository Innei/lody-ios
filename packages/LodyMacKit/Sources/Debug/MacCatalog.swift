import AppKit
import LodyData

@MainActor
enum MacCatalog {
  struct Scene {
    let id: String
    let title: String
    let size: NSSize
    let make: @MainActor () -> NSViewController
  }

  static var scenes: [Scene] {
    [
      Scene(id: "sign-in", title: "Sign in", size: NSSize(width: 560, height: 440)) {
        SignInViewController(service: .fixture(code: nil))
      },
      Scene(id: "sign-in-code", title: "Sign in · device code", size: NSSize(width: 560, height: 440)) {
        SignInViewController(service: .fixture(code: "WXYZ-1234"))
      },
    ]
  }

  static func make(_ id: String) -> NSViewController? {
    scenes.first { $0.id == id }?.make()
  }

  static func scene(_ id: String) -> Scene? { scenes.first { $0.id == id } }
}

extension SignInService {
  static let fixtureChanges = Notification.Name("LodyMacSignInFixtureDidChange")

  static func fixture(code initial: String?) -> SignInService {
    let box = FixtureBox(code: initial)
    return SignInService(
      snapshot: {
        AuthSnapshot(busy: false, code: box.code.map {
          AuthSnapshot.Code(user_code: $0, verification_uri_complete: "https://lody.ai/device", expires_in: 600, interval: 5)
        })
      },
      login: {
        box.code = "WXYZ-1234"
        NotificationCenter.default.post(name: fixtureChanges, object: nil)
      },
      cancel: {
        box.code = nil
        NotificationCenter.default.post(name: fixtureChanges, object: nil)
      },
      reopen: {},
      changes: fixtureChanges
    )
  }
}

@MainActor
private final class FixtureBox {
  var code: String?
  init(code: String?) { self.code = code }
}
