import AppKit

@MainActor
enum SidebarRowLayout {
  static let font = NSFont.preferredFont(forTextStyle: .body)

  static func installTitle(_ title: NSTextField, in row: NSView, unread: Bool = false) {
    title.font = unread ? .systemFont(ofSize: 13, weight: .medium) : font
    title.textColor = .labelColor
    title.lineBreakMode = .byTruncatingTail
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    title.translatesAutoresizingMaskIntoConstraints = false
    row.addSubview(title)
    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 36),
      title.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -36),
      title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
  }

  static func installIcon(_ icon: NSImageView, in row: NSView) {
    icon.contentTintColor = .secondaryLabelColor
    icon.setAccessibilityElement(false)
    icon.translatesAutoresizingMaskIntoConstraints = false
    row.addSubview(icon)
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
      icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 16),
      icon.heightAnchor.constraint(equalToConstant: 16),
    ])
  }
}

@MainActor
enum MacSidebarChrome {
  static func button(_ symbol: String, title: String, id: String, target: AnyObject, action: Selector, glass: Bool = false, size: CGFloat = 28) -> NSButton {
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
    let extent: CGFloat = glass ? 32 : size
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: extent),
      button.heightAnchor.constraint(equalToConstant: extent),
    ])
    return button
  }

  static func group(_ controls: [NSView]) -> NSView {
    let stack = NSStackView(views: controls)
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
    let glass = NSGlassEffectView()
    glass.style = .regular
    glass.cornerRadius = 22
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


/// Optical trailing space belongs to the native menu button's hit target.
@MainActor
final class MacAccountButton: NSPopUpButton {
  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(width: size.width + 10, height: size.height)
  }
}
