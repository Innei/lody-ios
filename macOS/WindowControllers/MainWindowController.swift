import AppKit
import LodyData

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  static let tabbingIdentifier = "app.innei.lody.mac.main"
  private static var open: [MainWindowController] = []
  let environment: MacEnvironment
  private(set) var workspace: MacWorkspaceController?
  private var observer: NSObjectProtocol?
  private var signedIn: Bool?
  private var onboarding: MacOnboardingChrome.Saved?

  init(environment: MacEnvironment = .live, sessionId: String? = nil) {
    self.environment = environment
    let window = environment.windowClass.init(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.toolbarStyle = .unified
    window.titleVisibility = .visible
    window.tabbingIdentifier = environment.titlePrefix + Self.tabbingIdentifier
    window.tabbingMode = .preferred
    window.minSize = NSSize(width: 760, height: 480)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier(environment.windowIdentifier)
    super.init(window: window)
    window.delegate = self
    let toolbar = NSToolbar(identifier: "lody.main")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    if environment.requiresAccount {
      observer = NotificationCenter.default.addObserver(forName: environment.authChanges, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.render() }
      }
    }
    render()
    workspace?.open(sessionId)
    Self.open.append(self)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  static var frontmost: MainWindowController? {
    open.first { $0.window?.isKeyWindow == true } ?? open.last
  }

  private func render() {
    let account = environment.requiresAccount ? environment.account() : nil
    let next = !environment.requiresAccount || account != nil
    guard next != signedIn else { return }
    signedIn = next
    if let workspace { MacTabCoordinator.shared.remove(workspace) }
    workspace = nil
    guard next else {
      window?.title = "Lody"
      window?.subtitle = ""
      guard let window else { return }
      let saved = onboarding ?? MacOnboardingChrome.Saved(frame: window.frame, minSize: window.minSize)
      window.contentViewController = environment.signIn()
      onboarding = MacOnboardingChrome.enter(window, keeping: saved)
      return
    }
    guard let signIn = window?.contentViewController as? SignInViewController, let user = account?.user else {
      showWorkspace()
      return
    }
    signIn.finish(name: user.name.isEmpty ? user.email : user.name) { [weak self] in
      guard self?.signedIn == true, self?.workspace == nil else { return }
      self?.showWorkspace()
    }
  }

  private func showWorkspace() {
    let workspace = MacWorkspaceController(environment: environment)
    let prefix = environment.titlePrefix
    workspace.onTitle = { [weak self] title, subtitle in
      self?.window?.title = prefix + title
      self?.window?.subtitle = subtitle
    }
    workspace.onBadge = { [weak self] badge in
      self?.window?.tab.accessoryView = badge.map(MacTabBadgeView.init)
    }
    workspace.onNewSession = { [weak self] in self?.workspace?.open(nil) }
    self.workspace = workspace
    window?.contentViewController = workspace
    if let window, onboarding != nil || window.titlebarAppearsTransparent {
      MacOnboardingChrome.leave(window, restoring: onboarding)
      onboarding = nil
    }
    window?.title = environment.titlePrefix + "Lody"
    MacTabCoordinator.shared.add(workspace)
    if window?.isKeyWindow == true { MacTabCoordinator.shared.select(workspace) }
  }

  @discardableResult
  func addTab(sessionId: String? = nil) -> MainWindowController {
    let next = MainWindowController(environment: environment, sessionId: sessionId)
    if let window, let tab = next.window {
      (window.tabbedWindows?.last ?? window).addTabbedWindow(tab, ordered: .above)
      tab.makeKeyAndOrderFront(nil)
    }
    return next
  }

  override func newWindowForTab(_ sender: Any?) {
    addTab()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    if let workspace { MacTabCoordinator.shared.select(workspace) }
  }

  func windowWillClose(_ notification: Notification) {
    if let workspace { MacTabCoordinator.shared.remove(workspace) }
    Self.open.removeAll { $0 === self }
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .lodyNewSession]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard itemIdentifier == .lodyNewSession else { return nil }
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = String(localized: "mac.sidebar.newSession", bundle: .lodyMac)
    item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: item.label)
    item.target = self
    item.action = #selector(newSessionPressed)
    return item
  }

  @objc private func newSessionPressed() { workspace?.open(nil) }

  override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
    guard let workspace, workspace.responds(to: action) else { return super.supplementalTarget(forAction: action, sender: sender) }
    return workspace
  }

  static func tabIndex(tag: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    if tag == 9 { return count - 1 }
    return (1...count).contains(tag) ? tag - 1 : nil
  }

  private var tabs: [NSWindow] { window.map { $0.tabbedWindows ?? [$0] } ?? [] }

  @objc func showTab(_ sender: NSMenuItem) {
    guard let index = Self.tabIndex(tag: sender.tag, count: tabs.count) else { return }
    window?.tabGroup?.selectedWindow = tabs[index]
    tabs[index].makeKeyAndOrderFront(nil)
  }
}

extension MainWindowController: NSMenuItemValidation {
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    guard item.action == #selector(showTab(_:)) else { return true }
    return Self.tabIndex(tag: item.tag, count: tabs.count) != nil
  }
}

extension NSToolbarItem.Identifier {
  static let lodyNewSession = NSToolbarItem.Identifier("lody.newSession")
}
