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
    title.lineBreakMode = .byTruncatingTail
    title.font = .systemFont(ofSize: 13, weight: row.unread ? .semibold : .regular)
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField = title
    let project = NSTextField(labelWithString: row.project)
    project.font = .systemFont(ofSize: 11)
    project.textColor = .secondaryLabelColor
    project.lineBreakMode = .byTruncatingTail
    project.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let projectGlyph = Self.symbol("folder", color: .systemIndigo)
    let heading = NSStackView(views: [projectGlyph])
    if row.pinned { heading.addArrangedSubview(Self.symbol("pin.fill", color: .tertiaryLabelColor)) }
    heading.addArrangedSubview(project)
    heading.spacing = 5
    let statusText = NSTextField(labelWithString: Self.time(row.activityAt))
    statusText.font = .systemFont(ofSize: 10)
    statusText.textColor = .secondaryLabelColor
    status.spacing = 4
    status.addArrangedSubview(statusText)
    if row.status == "error" {
      status.insertArrangedSubview(Self.symbol("exclamationmark.triangle.fill", color: .systemRed), at: 0)
      statusText.stringValue = String(localized: "mac.sidebar.failed", bundle: .lodyMac)
      statusText.textColor = .systemRed
    } else if row.attention {
      status.insertArrangedSubview(Self.symbol("hand.raised.fill", color: .systemOrange), at: 0)
      statusText.stringValue = String(localized: "mac.sidebar.needsYou", bundle: .lodyMac)
      statusText.textColor = .systemOrange
    } else if MacSessionStatus.busy(row.status) {
      let spinner = Self.symbol("circle.dotted", color: .systemIndigo)
      if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        spinner.addSymbolEffect(.rotate, options: .repeating)
      }
      status.insertArrangedSubview(spinner, at: 0)
      statusText.stringValue = String(localized: "mac.sidebar.working", bundle: .lodyMac)
    } else if row.unread && row.status == "completed" {
      status.insertArrangedSubview(Self.symbol("checkmark.circle", color: .systemIndigo), at: 0)
      statusText.stringValue = String(localized: "mac.sidebar.done", bundle: .lodyMac)
      statusText.textColor = .systemIndigo
    } else if row.unread {
      let unread = Self.symbol("circle.fill", color: .systemIndigo)
      unread.symbolConfiguration = .init(pointSize: 5, weight: .regular)
      status.insertArrangedSubview(unread, at: 0)
    }
    more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
    more.isBordered = false
    more.title = ""
    more.alphaValue = 0
    more.target = self
    more.action = #selector(showMenu)
    more.setAccessibilityLabel(String(localized: "mac.sidebar.sessionActions", bundle: .lodyMac))
    let statusSlot = NSView()
    for view in [status, more] {
      view.translatesAutoresizingMaskIntoConstraints = false
      statusSlot.addSubview(view)
    }
    NSLayoutConstraint.activate([
      status.leadingAnchor.constraint(greaterThanOrEqualTo: statusSlot.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: statusSlot.trailingAnchor),
      status.centerYAnchor.constraint(equalTo: statusSlot.centerYAnchor),
      statusSlot.widthAnchor.constraint(greaterThanOrEqualTo: status.widthAnchor),
      statusSlot.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
      statusSlot.heightAnchor.constraint(equalToConstant: 18),
      more.trailingAnchor.constraint(equalTo: statusSlot.trailingAnchor),
      more.centerYAnchor.constraint(equalTo: statusSlot.centerYAnchor),
      more.widthAnchor.constraint(equalToConstant: 22),
      more.heightAnchor.constraint(equalToConstant: 22),
    ])
    heading.addArrangedSubview(statusSlot)
    let detail = row.branch ?? row.machine ?? ""
    let context = NSTextField(labelWithString: detail)
    context.font = .systemFont(ofSize: 11)
    context.textColor = .secondaryLabelColor
    context.lineBreakMode = .byTruncatingMiddle
    context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let contextSymbol = row.branch == nil ? "desktopcomputer" : "arrow.triangle.branch"
    let meta = NSStackView(views: [Self.symbol(contextSymbol, color: .tertiaryLabelColor), context])
    meta.spacing = 5
    if !row.agent.isEmpty {
      let provider = Self.symbol(Self.agentSymbol(row.agent), color: .secondaryLabelColor)
      provider.toolTip = row.agent
      meta.addArrangedSubview(NSView())
      meta.addArrangedSubview(provider)
    }
    let stack = NSStackView(views: [heading, title, meta])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
      title.widthAnchor.constraint(equalTo: stack.widthAnchor),
      meta.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
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

  private static func agentSymbol(_ agent: String) -> String {
    switch agent {
    case "claude", "claude-code": "asterisk"
    case "codex": "hexagon"
    default: "sparkles"
    }
  }

  private static func symbol(_ name: String, color: NSColor) -> NSImageView {
    let view = NSImageView()
    view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    view.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    view.contentTintColor = color
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 14), view.heightAnchor.constraint(equalToConstant: 14)])
    return view
  }

  private static let timeFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.maximumUnitCount = 1
    formatter.unitsStyle = .abbreviated
    return formatter
  }()

  private static func time(_ timestamp: Double?) -> String {
    guard let timestamp, timestamp.isFinite else { return "" }
    let elapsed = max(0, Date().timeIntervalSince1970 - timestamp / 1000)
    if elapsed < 60 { return String(localized: "mac.sidebar.now", bundle: .lodyMac) }
    return timeFormatter.string(from: elapsed) ?? ""
  }
}

@MainActor
enum MacSessionStatus {
  static func busy(_ status: String) -> Bool { OutboxDispatcher.busy.contains(status) }
}
