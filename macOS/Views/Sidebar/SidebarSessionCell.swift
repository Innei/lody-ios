import AppKit
import LodyData
import Symbols

@MainActor
final class SidebarSessionCell: NSTableCellView {
  var menuForRow: (() -> NSMenu)?
  private let more = NSButton()
  private let status = NSStackView()
  private var hover: NSTrackingArea?

  init(row: MacSidebarModel.Row) {
    super.init(frame: .zero)
    let title = NSTextField(labelWithString: row.title)
    textField = title
    SidebarRowLayout.installTitle(title, in: self, unread: row.unread)
    let state = NSImageView()
    state.translatesAutoresizingMaskIntoConstraints = false
    state.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    var help = ""
    if row.status == "error" {
      state.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
      state.contentTintColor = .systemRed
      help = String(localized: "mac.sidebar.failed", bundle: .lodyMac)
    } else if row.attention {
      state.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
      state.contentTintColor = .systemOrange
      help = String(localized: "mac.sidebar.needsYou", bundle: .lodyMac)
    } else if MacSessionStatus.busy(row.status) {
      state.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: nil)
      state.contentTintColor = .systemIndigo
      help = String(localized: "mac.sidebar.working", bundle: .lodyMac)
      if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { state.addSymbolEffect(.rotate, options: .repeating) }
    } else if row.pinned {
      state.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
      state.contentTintColor = .secondaryLabelColor
    }
    if row.unread && row.status == "completed" { help = String(localized: "mac.sidebar.done", bundle: .lodyMac) }
    status.addArrangedSubview(state)
    status.translatesAutoresizingMaskIntoConstraints = false
    addSubview(status)
    let unread = NSImageView()
    unread.image = row.unread ? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) : nil
    unread.symbolConfiguration = .init(pointSize: 4, weight: .regular)
    unread.contentTintColor = .systemIndigo
    unread.translatesAutoresizingMaskIntoConstraints = false
    addSubview(unread)
    more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
    more.isBordered = false
    more.title = ""
    more.alphaValue = 0
    more.target = self
    more.action = #selector(showMenu)
    more.setAccessibilityLabel(String(localized: "mac.sidebar.sessionActions", bundle: .lodyMac))
    more.translatesAutoresizingMaskIntoConstraints = false
    addSubview(more)
    NSLayoutConstraint.activate([
      unread.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      unread.centerYAnchor.constraint(equalTo: centerYAnchor),
      unread.widthAnchor.constraint(equalToConstant: 8),
      unread.heightAnchor.constraint(equalToConstant: 8),
      status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      status.centerYAnchor.constraint(equalTo: centerYAnchor),
      state.widthAnchor.constraint(equalToConstant: 16),
      state.heightAnchor.constraint(equalToConstant: 16),
      more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      more.centerYAnchor.constraint(equalTo: centerYAnchor),
      more.widthAnchor.constraint(equalToConstant: 28),
      more.heightAnchor.constraint(equalToConstant: 28),
    ])
    setAccessibilityHelp(help)
    let detail = row.branch ?? row.machine ?? ""
    toolTip = [row.title, row.project, detail].filter { !$0.isEmpty }.joined(separator: "\n")
    setAccessibilityLabel(row.title)
    setAccessibilityIdentifier("session-" + row.id)
  }

  required init?(coder: NSCoder) { nil }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hover { removeTrackingArea(hover) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area)
    hover = area
  }

  override func mouseEntered(with event: NSEvent) {
    more.alphaValue = 1
    status.alphaValue = 0
  }

  override func mouseExited(with event: NSEvent) {
    more.alphaValue = 0
    status.alphaValue = 1
  }

  @objc private func showMenu() {
    menuForRow?().popUp(positioning: nil, at: NSPoint(x: bounds.maxX - 12, y: bounds.midY), in: self)
  }
}

@MainActor
enum MacSessionStatus {
  static func busy(_ status: String) -> Bool { OutboxDispatcher.busy.contains(status) }
}
