import AppKit

@MainActor
enum MacSidebarChrome {
  static func button(_ symbol: String, title: String, id: String, target: AnyObject, action: Selector, glass: Bool = false) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), target: target, action: action)
    button.title = ""
    button.bezelStyle = .accessoryBarAction
    button.isBordered = true
    button.showsBorderOnlyWhileMouseInside = true
    button.controlSize = .regular
    if glass {
      button.bezelStyle = .glass
      button.isBordered = true
      button.borderShape = .circle
    }
    button.toolTip = title
    button.setAccessibilityLabel(title)
    button.setAccessibilityIdentifier(id)
    button.translatesAutoresizingMaskIntoConstraints = false
    let size: CGFloat = glass ? 32 : 28
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: size),
      button.heightAnchor.constraint(equalToConstant: size),
    ])
    return button
  }

  static func group(_ controls: [NSView]) -> NSView {
    let stack = NSStackView(views: controls)
    stack.spacing = 2
    stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
    let glass = NSGlassEffectView()
    glass.cornerRadius = 18
    glass.contentView = stack
    if #available(macOS 27, *) { glass.effectIsInteractive = true }
    return glass
  }

  static func accessory(_ controls: [NSView]) -> NSSplitViewItemAccessoryViewController {
    let stack = NSStackView(views: controls)
    stack.spacing = 8
    stack.alignment = .centerY
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    let controller = NSSplitViewItemAccessoryViewController()
    controller.view = stack
    if #available(macOS 26.1, *) { controller.preferredScrollEdgeEffectStyle = .soft }
    return controller
  }
}

@MainActor
final class SidebarSearchField: NSTextField {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    isBezeled = false
    drawsBackground = false
    focusRingType = .none
    font = .systemFont(ofSize: 13)
    cell?.usesSingleLineMode = true
    setAccessibilitySubrole(.searchField)
  }

  required init?(coder: NSCoder) { nil }
}

@MainActor
final class SidebarSearchSurface: NSView {
  var focused = false { didSet { needsDisplay = true } }
  private let field: NSTextField
  private let clear = NSButton()

  init(field: NSTextField) {
    self.field = field
    super.init(frame: .zero)
    let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
    icon.contentTintColor = .secondaryLabelColor
    icon.setAccessibilityElement(false)
    clear.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
    clear.isBordered = false
    clear.contentTintColor = .secondaryLabelColor
    clear.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    clear.target = self
    clear.action = #selector(clearPressed)
    clear.setAccessibilityIdentifier("sidebar-search-clear")
    clear.setAccessibilityLabel(String(localized: "mac.sidebar.clearSearch", bundle: .lodyMac))
    for view in [icon, field, clear] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 32),
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14),
      field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
      field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
      field.centerYAnchor.constraint(equalTo: centerYAnchor),
      field.heightAnchor.constraint(equalToConstant: 22),
      clear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      clear.centerYAnchor.constraint(equalTo: centerYAnchor),
      clear.widthAnchor.constraint(equalToConstant: 24), clear.heightAnchor.constraint(equalToConstant: 24),
    ])
    updateValue()
  }

  required init?(coder: NSCoder) { nil }

  func updateValue() { clear.isHidden = field.stringValue.isEmpty }

  @objc private func clearPressed() {
    field.stringValue = ""
    field.currentEditor()?.string = ""
    updateValue()
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    window?.makeFirstResponder(field)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
    path.fill()
    let border = focused ? NSColor.lodyAccent.withAlphaComponent(0.7) : NSColor.separatorColor
    border.setStroke()
    path.lineWidth = 1
    path.stroke()
  }
}
