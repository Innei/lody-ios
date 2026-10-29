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

  init(environment: MacEnvironment = .live, sessionId: String? = nil) {
    self.environment = environment
    let window = NSWindow(
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
      observer = NotificationCenter.default.addObserver(forName: .lodyAuthDidChange, object: nil, queue: .main) { [weak self] _ in
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
    let next = !environment.requiresAccount || AuthSession.shared.snapshot.account != nil
    guard next != signedIn else { return }
    signedIn = next
    if let workspace { MacTabCoordinator.shared.remove(workspace) }
    workspace = nil
    guard next else {
      window?.title = "Lody"
      window?.subtitle = ""
      window?.contentViewController = SignInViewController()
      return
    }
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
}

extension NSToolbarItem.Identifier {
  static let lodyNewSession = NSToolbarItem.Identifier("lody.newSession")
}

@MainActor
final class MacPlaceholderController: NSViewController {
  private let text: String

  init(text: String) {
    self.text = text
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let label = NSTextField(labelWithString: text)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    root.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
  }
}

@MainActor
final class MacTabBadgeView: NSImageView {
  convenience init(_ badge: MacTabBadge) {
    switch badge {
    case .approval:
      self.init(image: NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil) ?? NSImage())
      symbolConfiguration = .init(pointSize: 10, weight: .regular)
      contentTintColor = .systemOrange
      setAccessibilityIdentifier("tab-badge-approval")
    case .working:
      self.init(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage())
      symbolConfiguration = .init(pointSize: 7, weight: .bold)
      contentTintColor = .lodyAccent
      setAccessibilityIdentifier("tab-badge-working")
    }
  }
}
