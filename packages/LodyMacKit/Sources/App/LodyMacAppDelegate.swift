import AppKit
import LodyData

@MainActor
public final class LodyMacAppDelegate: NSObject, NSApplicationDelegate {
  private let host = MacHost()
  private let runtime = DataRuntime(localStore: .shared)
  private var settings: NSWindowController?
  private var debug: NSWindowController?

  override public init() { super.init() }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MacMainMenu.make(target: self)
    LodyHosting.current = host
    host.watchMemoryPressure()
    NSWindow.allowsAutomaticWindowTabbing = true
    if LodyUIVerify.enabled {
      URLProtocol.registerClass(OfflineProbe.self)
      #if DEBUG
      if LodyUIVerify.offscreen {
        NSApp.setActivationPolicy(.accessory)
      } else {
        showDebug()
      }
      #endif
      return
    }
    DataRuntime.current = runtime
    AuthSession.shared.stopRuntime = { [weak self] in self?.runtime.stop() }
    OutboxSession.shared.attach(runtime)
    CatalogSession.shared.attach(runtime)
    MacNotifier.shared.onOpen = { [weak self] sessionId in
      NSApp.activate()
      self?.showMain()
      MainWindowController.frontmost?.workspace?.open(sessionId)
    }
    MacNotifier.shared.start()
    showMain()
    AuthSession.shared.start()
  }

  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag && !LodyUIVerify.enabled { showMain() }
    return true
  }

  public func application(_ application: NSApplication, open urls: [URL]) {
    #if DEBUG
    for url in urls { route(url) }
    #endif
  }

  #if DEBUG
  private func route(_ url: URL) {
    guard let route = MacVerifyRoute(url) else { return }
    switch route {
    case .scene(let id): MacSceneHost.shared.open(id)
    case .reset: MacSceneHost.shared.reset()
    case .appearance(let mode):
      let names: [String: NSAppearance.Name] = ["light": .aqua, "dark": .darkAqua]
      NSApp.appearance = names[mode].flatMap(NSAppearance.init(named:))
    case .snapshot(let out):
      guard let window = MacSceneHost.shared.front else { return }
      do { try MacViewDump.snapshot(window, to: out) } catch {
        DiagnosticsStore.shared.record("mac", "snapshot_failed", fields: ["code": String((error as NSError).code)])
      }
    case .act(let seq, let action):
      MacVerifyActions.run(seq, action, in: MacSceneHost.shared.front)
    case .dump(let out):
      do { try MacViewDump.write(to: out) } catch {
        DiagnosticsStore.shared.record("mac", "dump_failed", fields: ["code": String((error as NSError).code)])
      }
    }
  }
  #endif

  func showMain() {
    let controller = MainWindowController.frontmost ?? MainWindowController()
    controller.showWindow(nil)
  }

  @objc func newSessionTab(_ sender: Any?) {
    showMain()
    MainWindowController.frontmost?.workspace?.open(nil)
  }

  @objc func showSettings(_ sender: Any?) {
    let controller = settings ?? Self.window(MacSettingsController(), title: String(localized: "mac.settings.title", bundle: .lodyMac), id: "settings")
    settings = controller
    controller.showWindow(nil)
  }

  #if DEBUG
  @objc func showDebug(_ sender: Any? = nil) {
    let controller = debug ?? Self.window(MacDebugController(), title: "Debug", id: "debug")
    debug = controller
    controller.showWindow(nil)
  }
  #endif

  private static func window(_ content: NSViewController, title: String, id: String) -> NSWindowController {
    let window = NSWindow(contentViewController: content)
    window.title = title
    window.identifier = NSUserInterfaceItemIdentifier(id)
    window.styleMask.remove(.miniaturizable)
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.center()
    return NSWindowController(window: window)
  }
}
