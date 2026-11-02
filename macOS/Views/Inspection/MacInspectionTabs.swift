import AppKit

/// Native controls with explicit geometry shared by the titlebar and file surfaces.
@MainActor
final class MacInspectionTabs: NSView {
  var select: ((MacInspectionState.Selection) -> Void)?
  var close: ((MacInspectionTarget) -> Void)?
  var pin: ((MacInspectionTarget) -> Void)?
  private let changes = MacInspectionTab(title: String(localized: "mac.inspection.changes", bundle: .lodyMac), symbol: "arrow.triangle.branch")
  private let scroll = NSScrollView()
  private let files = NSStackView()
  private var previousSelection: MacInspectionState.Selection?

  override init(frame: NSRect) {
    super.init(frame: frame)
    changes.button.setAccessibilityIdentifier("inspection-changes-tab")
    changes.button.invoke = { [weak self] in self?.select?(.changes) }
    files.orientation = .horizontal; files.spacing = 4
    files.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = files; scroll.drawsBackground = false
    scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
    scroll.horizontalScrollElasticity = .allowed
    let row = NSStackView(views: [changes, scroll]); row.spacing = 4
    row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
      changes.widthAnchor.constraint(equalToConstant: 104), changes.heightAnchor.constraint(equalToConstant: 35),
      scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 0), scroll.heightAnchor.constraint(equalToConstant: 35),
      files.heightAnchor.constraint(equalTo: scroll.heightAnchor),
      files.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), files.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
    ])
  }
  required init?(coder: NSCoder) { nil }

  func render(_ state: MacInspectionState) {
    changes.selected = state.selection == .changes
    let selectionChanged = previousSelection != state.selection
    previousSelection = state.selection
    let origin = scroll.contentView.bounds.origin
    var selected: NSView?
    files.arrangedSubviews.forEach { files.removeArrangedSubview($0); $0.removeFromSuperview() }
    for tab in state.tabs {
      let pill = MacInspectionTab(title: tab.target.name, symbol: ["png", "jpg", "jpeg"].contains((tab.target.name as NSString).pathExtension) ? "photo" : "doc.text")
      pill.selected = state.selection == .document(tab.target)
      pill.button.invoke = { [weak self] in self?.select?(.document(tab.target)) }
      pill.button.onPin = { [weak self] in self?.pin?(tab.target) }
      pill.button.font = tab.pinned ? .systemFont(ofSize: 13) : NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
      pill.button.toolTip = tab.target.path
      pill.button.setAccessibilityIdentifier("inspection-tab-" + tab.target.path)
      let close = MacInspectionUI.icon("xmark", title: String(localized: "mac.inspection.closeFile", bundle: .lodyMac) + " " + tab.target.name, id: "inspection-close-" + tab.target.path, size: 20) { [weak self] _ in self?.close?(tab.target) }
      pill.addClose(close)
      let textWidth = (tab.target.name as NSString).size(withAttributes: [.font: pill.button.font ?? NSFont.systemFont(ofSize: 13)]).width
      pill.widthAnchor.constraint(equalToConstant: min(250, max(120, textWidth + 62))).isActive = true
      pill.heightAnchor.constraint(equalToConstant: 35).isActive = true
      files.addArrangedSubview(pill)
      if pill.selected { selected = pill }
    }
    files.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: origin)
    if selectionChanged, let selected { scroll.layoutSubtreeIfNeeded(); selected.scrollToVisible(selected.bounds) }
  }
}

@MainActor
private final class MacInspectionTab: MacInspectionSurface {
  let button = MacInspectionTabButton()
  var selected = false { didSet { fill = selected ? .textBackgroundColor : .clear; outline = selected; button.contentTintColor = selected ? .labelColor : .secondaryLabelColor; needsDisplay = true } }
  private let row = NSStackView()
  init(title: String, symbol: String? = nil) {
    super.init(frame: .zero)
    radius = 8
    button.title = title; button.font = .systemFont(ofSize: 13); button.alignment = .left
    button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)); button.imagePosition = .imageLeading }
    row.addArrangedSubview(button); row.spacing = 4
    row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
      row.centerYAnchor.constraint(equalTo: centerYAnchor), row.heightAnchor.constraint(equalToConstant: 28),
    ])
  }
  required init?(coder: NSCoder) { nil }
  func addClose(_ close: NSButton) { row.addArrangedSubview(close) }
}

@MainActor
private final class MacInspectionTabButton: NSButton {
  var invoke: (() -> Void)?
  var onPin: (() -> Void)?
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false; setButtonType(.momentaryPushIn); focusRingType = .none
    target = self; action = #selector(pressed); lineBreakMode = .byTruncatingMiddle
    menu = NSMenu()
    let item = NSMenuItem(title: String(localized: "mac.inspection.keepTab", bundle: .lodyMac), action: #selector(keep), keyEquivalent: "")
    item.target = self; menu?.addItem(item)
  }
  required init?(coder: NSCoder) { nil }
  override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); if event.clickCount == 2 { onPin?() } }
  @objc private func pressed() { invoke?() }
  @objc private func keep() { onPin?() }
}

@MainActor
class MacInspectionSurface: NSView {
  var fill: NSColor = .textBackgroundColor
  var radius: CGFloat = 0
  var outline = false
  var bottomRule = false
  var topRule = false
  var leadingRule = false
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    fill.setFill()
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: outline ? 0.5 : 0, dy: outline ? 0.5 : 0), xRadius: radius, yRadius: radius)
    path.fill()
    NSColor.separatorColor.setStroke()
    if outline { path.lineWidth = 0.5; path.stroke() }
    let rules = NSBezierPath(); rules.lineWidth = 0.5
    if bottomRule { rules.move(to: .init(x: 0, y: bounds.maxY - 0.25)); rules.line(to: .init(x: bounds.maxX, y: bounds.maxY - 0.25)) }
    if topRule { rules.move(to: .init(x: 0, y: 0.25)); rules.line(to: .init(x: bounds.maxX, y: 0.25)) }
    if leadingRule { rules.move(to: .init(x: 0.25, y: 0)); rules.line(to: .init(x: 0.25, y: bounds.maxY)) }
    rules.stroke()
  }
}

@MainActor
final class MacInspectionIconButton: NSButton {
  var invoke: ((NSView) -> Void)?
  private var hovering = false
  private var tracking: NSTrackingArea?
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false; bezelStyle = .accessoryBarAction; focusRingType = .none
    imagePosition = .imageOnly; contentTintColor = .secondaryLabelColor
    target = self; action = #selector(pressed)
  }
  required init?(coder: NSCoder) { nil }
  override func updateTrackingAreas() {
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
    if let tracking { addTrackingArea(tracking) }; super.updateTrackingAreas()
  }
  override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
  override func draw(_ dirtyRect: NSRect) {
    if hovering || state == .on {
      NSColor.quaternaryLabelColor.withAlphaComponent(0.1).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }
  @objc private func pressed() { invoke?(self) }
}
