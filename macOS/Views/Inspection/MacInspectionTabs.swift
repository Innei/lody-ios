import AppKit

@MainActor
final class MacInspectionTabs: NSView {
  var select: ((MacInspectionState.Selection) -> Void)?
  var close: ((MacInspectionTarget) -> Void)?
  var pin: ((MacInspectionTarget) -> Void)?
  private let changes = NSButton()
  private let scroll = NSScrollView()
  private let files = NSStackView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    changes.title = String(localized: "mac.inspection.changes", bundle: .lodyMac)
    changes.image = NSImage(systemSymbolName: "plus.forwardslash.minus", accessibilityDescription: nil)
    changes.imagePosition = .imageLeading
    changes.bezelStyle = .accessoryBarAction
    changes.target = self; changes.action = #selector(showChanges)
    changes.setAccessibilityIdentifier("inspection-changes-tab")
    files.orientation = .horizontal; files.spacing = 4; files.translatesAutoresizingMaskIntoConstraints = false
    files.setHuggingPriority(.required, for: .vertical)
    scroll.documentView = files; scroll.drawsBackground = false
    scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
    let row = NSStackView(views: [changes, scroll])
    row.spacing = 4; row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
      files.heightAnchor.constraint(equalTo: scroll.heightAnchor),
      files.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), files.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
    ])
  }
  required init?(coder: NSCoder) { nil }

  func render(_ state: MacInspectionState) {
    changes.state = state.selection == .changes ? .on : .off
    files.arrangedSubviews.forEach { files.removeArrangedSubview($0); $0.removeFromSuperview() }
    for tab in state.tabs {
      let button = MacInspectionTabButton(title: tab.target.name) { [weak self] in self?.select?(.document(tab.target)) }
      button.onPin = { [weak self] in self?.pin?(tab.target) }
      button.font = tab.pinned ? .systemFont(ofSize: 12) : NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
      button.state = state.selection == .document(tab.target) ? .on : .off
      button.toolTip = tab.target.path
      button.setAccessibilityIdentifier("inspection-tab-" + tab.target.path)
      let close = MacActionButton(title: "") { [weak self] in self?.close?(tab.target) }
      close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      close.isBordered = false
      close.setAccessibilityLabel(String(localized: "mac.inspection.closeFile", bundle: .lodyMac) + " " + tab.target.name)
      close.setAccessibilityIdentifier("inspection-close-" + tab.target.path)
      let row = NSStackView(views: [button, close]); row.spacing = 0
      button.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
      close.widthAnchor.constraint(equalToConstant: 22).isActive = true
      files.addArrangedSubview(row)
    }
  }
  @objc private func showChanges() { select?(.changes) }
}

@MainActor
private final class MacInspectionTabButton: NSButton {
  var onPin: (() -> Void)?
  private let invoke: () -> Void
  init(title: String, invoke: @escaping () -> Void) {
    self.invoke = invoke
    super.init(frame: .zero)
    self.title = title; bezelStyle = .accessoryBarAction
    setButtonType(.toggle)
    target = self; action = #selector(pressed)
    lineBreakMode = .byTruncatingMiddle
    menu = NSMenu()
    let item = NSMenuItem(title: String(localized: "mac.inspection.keepTab", bundle: .lodyMac), action: #selector(keep), keyEquivalent: "")
    item.target = self; menu?.addItem(item)
  }
  required init?(coder: NSCoder) { nil }
  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    if event.clickCount == 2 { onPin?() }
  }
  @objc private func pressed() { invoke() }
  @objc private func keep() { onPin?() }
}
