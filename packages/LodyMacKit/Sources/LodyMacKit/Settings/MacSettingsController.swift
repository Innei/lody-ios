import AppKit
import LodyData

@MainActor
final class MacSettingsController: NSViewController {
  private let account = NSTextField(labelWithString: "")
  private let signOut = NSButton(title: String(localized: "mac.settings.signOut", bundle: .lodyMac), target: nil, action: nil)
  private var observer: NSObjectProtocol?

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: String(localized: "mac.settings.account", bundle: .lodyMac)), account],
      [NSGridCell.emptyContentView, signOut],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.rowSpacing = 12
    grid.columnSpacing = 12
    signOut.target = self
    signOut.action = #selector(signOutPressed)
    var rows: [NSView] = [grid]
    #if DEBUG
    let debug = NSButton(title: "Debug…", target: NSApp.delegate, action: #selector(LodyMacAppDelegate.showDebug(_:)))
    rows.append(debug)
    #endif
    let stack = NSStackView(views: rows)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 20
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    observer = NotificationCenter.default.addObserver(forName: .lodyAuthDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  private func render() {
    let user = AuthSession.shared.snapshot.account?.user
    account.stringValue = user.map { $0.email.isEmpty ? $0.name : $0.email } ?? String(localized: "mac.settings.signedOut", bundle: .lodyMac)
    signOut.isEnabled = user != nil
  }

  @objc private func signOutPressed() {
    Task { await AuthSession.shared.logout() }
  }
}
