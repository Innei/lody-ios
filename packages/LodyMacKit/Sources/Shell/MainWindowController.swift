import AppKit
import LodyData

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
  static let tabbingIdentifier = "app.innei.lody.mac.main"
  private var observer: NSObjectProtocol?
  private var signedIn: Bool?

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.tabbingIdentifier = Self.tabbingIdentifier
    window.tabbingMode = .preferred
    window.setFrameAutosaveName("LodyMain")
    window.minSize = NSSize(width: 720, height: 480)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("main")
    super.init(window: window)
    window.delegate = self
    observer = NotificationCenter.default.addObserver(forName: .lodyAuthDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  private func render() {
    let account = AuthSession.shared.snapshot.account
    let next = account != nil
    guard next != signedIn else { return }
    signedIn = next
    window?.title = "Lody"
    window?.contentViewController = next ? workspaceContent() : SignInViewController()
  }

  func workspaceContent() -> NSViewController {
    MacPlaceholderController(text: String(localized: "mac.workspace.loading", bundle: .lodyMac))
  }

  func newTab() {
    window?.makeKeyAndOrderFront(nil)
  }
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
