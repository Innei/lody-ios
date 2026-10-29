import AppKit
import LodyData

@MainActor
final class MacSettingsController: NSViewController {
  private let account = NSTextField(labelWithString: "")
  private let signOut = NSButton(title: String(localized: "mac.settings.signOut", bundle: .lodyMac), target: nil, action: nil)
  private let accent = NSPopUpButton()
  private let notifications = NSSwitch()
  private var observer: NSObjectProtocol?

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: String(localized: "mac.settings.account", bundle: .lodyMac)), account],
      [NSGridCell.emptyContentView, signOut],
      [NSTextField(labelWithString: String(localized: "mac.settings.accent", bundle: .lodyMac)), accent],
      [NSTextField(labelWithString: String(localized: "mac.settings.notifications", bundle: .lodyMac)), notificationRow()],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.rowSpacing = 12
    grid.columnSpacing = 12
    signOut.target = self
    signOut.action = #selector(signOutPressed)
    for choice in MacAccent.allCases {
      accent.addItem(withTitle: choice.label)
      accent.lastItem?.image = Self.swatch(choice.color)
      accent.lastItem?.representedObject = choice.rawValue
    }
    accent.target = self
    accent.action = #selector(accentChanged)
    accent.setAccessibilityIdentifier("settings-accent")
    notifications.target = self
    notifications.action = #selector(notificationsChanged)
    notifications.setAccessibilityIdentifier("settings-notifications")
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
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 300))
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
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
    accent.selectItem(at: MacAccent.allCases.firstIndex(of: .current()) ?? 0)
    notifications.state = MacNotifier.shared.enabled ? .on : .off
  }

  private func notificationRow() -> NSView {
    let detail = NSTextField(wrappingLabelWithString: String(localized: "mac.settings.notifications.detail", bundle: .lodyMac))
    detail.textColor = .secondaryLabelColor
    detail.font = .systemFont(ofSize: 12)
    detail.preferredMaxLayoutWidth = 320
    let row = NSStackView(views: [notifications, detail])
    row.alignment = .top
    row.spacing = 10
    return row
  }

  private static func swatch(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
      return true
    }
  }

  @objc private func accentChanged() {
    let raw = accent.selectedItem?.representedObject as? String
    (raw.flatMap(MacAccent.init(rawValue:)) ?? .system).apply()
  }

  @objc private func notificationsChanged() {
    let on = notifications.state == .on
    Task { [weak self] in
      let granted = await MacNotifier.shared.setEnabled(on)
      self?.notifications.state = granted ? .on : .off
    }
  }

  @objc private func signOutPressed() {
    Task { await AuthSession.shared.logout() }
  }
}
