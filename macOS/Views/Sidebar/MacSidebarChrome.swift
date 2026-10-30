import AppKit

@MainActor
enum MacSidebarChrome {
  static func button(_ symbol: String, title: String, id: String, target: AnyObject, action: Selector, glass: Bool = false) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), target: target, action: action)
    button.title = ""
    button.bezelStyle = .accessoryBarAction
    button.isBordered = false
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
