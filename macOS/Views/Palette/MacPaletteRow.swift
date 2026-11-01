import AppKit

@MainActor
final class MacPaletteRow: NSTableRowView {
  var onHover: (() -> Void)?
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
  private var hovered = false
  private var tracking: NSTrackingArea?

  override func updateTrackingAreas() {
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    tracking = area
    addTrackingArea(area)
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) { hovered = true; onHover?(); needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func drawBackground(in dirtyRect: NSRect) { if hovered && !isSelected { highlight() } }
  override func drawSelection(in dirtyRect: NSRect) { highlight() }

  private func highlight() {
    NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 7, yRadius: 7).fill()
  }

  static func cell(_ item: MacPaletteModel.Item) -> NSView {
    let cell = NSTableCellView()
    let icon = NSImageView(image: NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) ?? NSImage())
    icon.contentTintColor = .secondaryLabelColor
    icon.setAccessibilityElement(false)
    let title = NSTextField(labelWithString: item.title)
    title.font = .preferredFont(forTextStyle: .body)
    title.lineBreakMode = .byTruncatingTail
    let context = NSTextField(labelWithString: item.context)
    context.font = .preferredFont(forTextStyle: .caption1)
    context.textColor = .secondaryLabelColor
    context.lineBreakMode = .byTruncatingMiddle
    context.alignment = .right
    context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    cell.textField = title
    cell.setAccessibilityIdentifier("palette-row-" + item.id)
    for child in [icon, title, context] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
      icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
      icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      title.trailingAnchor.constraint(lessThanOrEqualTo: context.leadingAnchor, constant: -12),
      context.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
      context.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
      context.widthAnchor.constraint(lessThanOrEqualTo: cell.widthAnchor, multiplier: 0.52),
    ])
    return cell
  }
}
