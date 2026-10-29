import AppKit
import LodyData

@MainActor
enum MacCatalog {
  struct Scene {
    let id: String
    let title: String
    let build: @MainActor () -> [NSWindow]

    init(id: String, title: String, size: NSSize, make: @escaping @MainActor () -> NSViewController) {
      self.id = id
      self.title = title
      build = { [MacSceneHost.window(make(), title: title, size: size)] }
    }

    init(id: String, title: String, windows: @escaping @MainActor () -> [NSWindow]) {
      self.id = id
      self.title = title
      build = windows
    }
  }

  static var scenes: [Scene] {
    [
      Scene(id: "sign-in", title: "Sign in", size: NSSize(width: 560, height: 440)) {
        SignInViewController(service: .fixture(code: nil))
      },
      Scene(id: "sign-in-code", title: "Sign in · device code", size: NSSize(width: 560, height: 440)) {
        SignInViewController(service: .fixture(code: "WXYZ-1234"))
      },
      Scene(id: "sidebar", title: "Sidebar") { MacFixtures.workspaceWindow(sessionId: "s-mac") },
      Scene(id: "tabs", title: "Tabs") { MacFixtures.tabbedWindows() },
    ]
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
