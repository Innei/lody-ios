#if DEBUG
import AppKit
import LodyData

@MainActor
enum DebugSceneFactory {
  struct Scene {
    let id: String
    let title: String
    let build: @MainActor () -> [NSWindow]

    init(id: String, title: String, size: NSSize, make: @escaping @MainActor () -> NSViewController) {
      self.id = id
      self.title = title
      build = { [DebugSceneCoordinator.window(make(), title: title, size: size)] }
    }

    init(id: String, title: String, windows: @escaping @MainActor () -> [NSWindow]) {
      self.id = id
      self.title = title
      build = windows
    }
  }

  static var scenes: [Scene] {
    [
      Scene(id: "sign-in", title: "Sign in") { [signInWindow(code: nil, title: "Sign in")] },
      Scene(id: "sign-in-code", title: "Sign in · device code") { [signInWindow(code: "WXYZ-1234", title: "Sign in · device code")] },
      Scene(id: "sign-in-done", title: "Sign in · signed in") {
        [signInWindow(code: "WXYZ-1234", title: "Sign in · signed in", finished: "Innei")]
      },
      Scene(id: "sidebar", title: "Sidebar") { MacFixtures.workspaceWindow(sessionId: "s-mac") },
      Scene(id: "tabs", title: "Tabs") { MacFixtures.tabbedWindows() },
      Scene(id: "transcript", title: "Transcript") { MacFixtures.workspaceWindow(sessionId: "s-mac") },
      Scene(id: "transcript-history", title: "Transcript · long history") { MacFixtures.workspaceWindow(sessionId: "s-mac", history: 1000) },
      Scene(id: "transcript-media", title: "Transcript · images and files") { MacFixtures.workspaceWindow(sessionId: "s-mac", media: true) },
      Scene(id: "transcript-history-10k", title: "Transcript · 10,000 entries") { MacFixtures.workspaceWindow(sessionId: "s-mac", history: 10000) },
      Scene(id: "attachments", title: "Composer · attachments") { MacFixtures.workspaceWindow(sessionId: "s-mac", attachments: true) },
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

  static func signInWindow(code: String?, title: String, finished: String? = nil) -> NSWindow {
    let controller = SignInViewController(service: .fixture(code: code))
    let window = DebugSceneCoordinator.window(controller, title: title, size: MacOnboardingChrome.size)
    MacOnboardingChrome.enter(window)
    if let finished { controller.finish(name: finished) {} }
    return window
  }

  static func settingsWindow(page: MacSettingsPage) -> NSWindow {
    let suite = "lody.mac.settings.catalog"
    UserDefaults().removePersistentDomain(forName: suite)
    let model = MacSettingsModel(services: .fixture, defaults: UserDefaults(suiteName: suite) ?? .standard)
    model.selection = page
    let window = SettingsWindowFactory.make(model: model, windowClass: MacOffscreen.windowClass).window ?? NSWindow()
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
      general: .fixture,
      appearance: .fixture,
      machines: .fixture,
      workspace: .fixture,
      projects: .fixture
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

extension MacMachineServices {
  static var fixture: MacMachineServices {
    let machines = [
      MacMachine(id: "m-studio", name: "Mac Studio", detail: "macOS 27", readOnly: false),
      MacMachine(id: "m-mini", name: "Mac mini", detail: "macOS 27", readOnly: false),
      MacMachine(id: "m-build", name: "Build Box", detail: "Ubuntu 26.04", readOnly: true),
    ]
    let names = MachineNames()
    return MacMachineServices(
      load: { _ in machines.map { names.apply($0) } },
      rename: { _, machine, name in
        names.values[machine.id] = name
        return machines.map { names.apply($0) }
      },
      presence: { SettingsMachinePresence(state: "live", onlineMachineIds: ["m-studio", "m-build"]) }
    )
  }

  @MainActor
  private final class MachineNames {
    var values: [String: String] = [:]

    func apply(_ machine: MacMachine) -> MacMachine {
      var renamed = machine
      renamed.name = values[machine.id] ?? machine.name
      return renamed
    }
  }
}

extension MacWorkspaceServices {
  static var fixture: MacWorkspaceServices {
    let members = WorkspaceMembers(members: [
      .init(id: "u-fixture", name: "Innei", email: "i@innei.dev", role: "owner"),
      .init(id: "u-ada", name: "Ada Park", email: "ada@example.com", role: "admin"),
      .init(id: "u-sam", name: "", email: "sam@example.com", role: "member"),
    ], role: "owner")
    return MacWorkspaceServices(members: { _ in members }, rename: { _, _ in }, setIcon: { _, _ in }, pickIcon: { nil })
  }
}

extension MacProjectServices {
  static var fixture: MacProjectServices {
    let catalog = SettingsCatalog(
      projects: [
        SettingsProject(id: "m-studio:local:p1", machineId: "m-studio", name: "lody-ios", rootPath: "~/git/lody-ios"),
        SettingsProject(id: "m-studio:local:p2", machineId: "m-studio", name: "handbook", rootPath: "~/git/handbook"),
        SettingsProject(id: "m-build:local:p3", machineId: "m-build", name: "infra", rootPath: "/srv/infra"),
      ],
      machineNames: ["m-studio": "Mac Studio", "m-build": "Build Box"]
    )
    var visibility = MacVisibility(userId: "u-fixture", rows: [
      .init(machineId: "m-studio", localProjectId: "p1", ownerUserId: "u-fixture", sharedWithTeam: true, updatedAt: 0),
      .init(machineId: "m-studio", localProjectId: "p2", ownerUserId: "u-fixture", sharedWithTeam: false, updatedAt: 0),
      .init(machineId: "m-build", localProjectId: "p3", ownerUserId: "u-ada", sharedWithTeam: true, updatedAt: 0),
    ])
    let presence = SettingsMachinePresence(state: "live", onlineMachineIds: ["m-studio", "m-build"])
    return MacProjectServices(
      workspace: { SettingsWorkspace(userId: "u-fixture", workspaceId: "w-lab", presence: presence, catalog: catalog) },
      list: { _ in visibility },
      share: { _, row, shared in
        for index in visibility.rows.indices where visibility.rows[index].localProjectId == row.localProjectId {
          visibility.rows[index].sharedWithTeam = shared
        }
        return visibility
      }
    )
  }
}

extension MacAppearanceServices {
  static var fixture: MacAppearanceServices {
    let box = MacAppearanceFixture()
    return MacAppearanceServices(
      theme: { box.theme }, setTheme: { box.theme = $0 },
      accent: { .current() }, setAccent: { $0.apply() },
      reading: { box.reading }, setReading: { box.reading = $0 }
    )
  }
}

@MainActor
private final class MacAppearanceFixture {
  var theme = MacTheme.system
  var reading = MacReading.standard
}

@MainActor
private final class MacGeneralFixture {
  var queued = "queue"
  var notifications = true
  var login = false
}
#endif
