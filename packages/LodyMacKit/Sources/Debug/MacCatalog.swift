#if DEBUG
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
      Scene(id: "transcript", title: "Transcript") { MacFixtures.workspaceWindow(sessionId: "s-mac") },
      Scene(id: "composer-new", title: "Composer · new session") { MacFixtures.workspaceWindow(sessionId: nil) },
      Scene(id: "composer-reply", title: "Composer · reply") { MacFixtures.workspaceWindow(sessionId: "s-mac") },
      Scene(id: "accent", title: "Accent") {
        MacAccent.system.apply()
        let workspace = MacFixtures.workspaceWindow(sessionId: "s-mac")
        let settings = settingsWindow(page: .appearance)
        if let frame = workspace.first?.frame { settings.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 300, y: frame.maxY - 60)) }
        return workspace + [settings]
      },
      Scene(id: "settings", title: "Settings") { [settingsWindow(page: .general)] },
    ]
  }

  static func scene(_ id: String) -> Scene? { scenes.first { $0.id == id } }

  static func settingsWindow(page: MacSettingsPage) -> NSWindow {
    let suite = "lody.mac.settings.catalog"
    UserDefaults().removePersistentDomain(forName: suite)
    let model = MacSettingsModel(services: .fixture, defaults: UserDefaults(suiteName: suite) ?? .standard)
    model.selection = page
    let window = MacSettingsWindow.make(model: model, windowClass: MacOffscreen.windowClass).window ?? NSWindow()
    window.setFrameAutosaveName("")
    window.identifier = NSUserInterfaceItemIdentifier("catalog-scene")
    window.center()
    return window
  }
}

extension MacSettingsServices {
  static var fixture: MacSettingsServices {
    let user = AuthUser(id: "u-fixture", name: "Innei", email: "i@innei.dev", image: nil)
    let workspaces = MacFixtures.listState.workspaces + [AuthWorkspace(id: "w-side", name: "Side Projects", slug: "side", image: nil)]
    let state = SettingsState(account: AuthAccount(user: user, workspaces: workspaces), workspace: workspaces.first)
    return MacSettingsServices(
      source: SettingsSource(changes: [], read: { state }, refresh: {}, logout: {}),
      selectWorkspace: { _ in },
      signIn: {},
      general: .fixture
    )
  }
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
extension MacGeneralServices {
  static var fixture: MacGeneralServices {
    let box = MacGeneralFixture()
    return MacGeneralServices(
      queued: { box.queued },
      saveQueued: { box.queued = $0 },
      notifications: { box.notifications },
      setNotifications: { on in
        box.notifications = on
        return on
      },
      loginItem: MacLoginItem(
        status: { box.login ? .enabled : .disabled },
        register: { box.login = true },
        unregister: { box.login = false },
        openSystemSettings: {}
      )
    )
  }
}

@MainActor
private final class MacGeneralFixture {
  var queued = "queue"
  var notifications = true
  var login = false
}
#endif
