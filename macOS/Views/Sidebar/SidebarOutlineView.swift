import AppKit
import LodyData

final class SidebarOutlineView: NSOutlineView {
  var onReturn: (() -> Void)?

  override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
    var rect = super.frameOfCell(atColumn: column, row: row)
    rect.origin.x = 8
    rect.size.width = max(0, bounds.width - 16)
    return rect
  }

  override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, selectedRow >= 0 {
      onReturn?()
      return
    }
    super.keyDown(with: event)
  }
}

final class SidebarRowView: NSTableRowView {
  override var isEmphasized: Bool {
    get { false }
    set {}
  }
}

final class SidebarActionButton: NSButton {
  private var hover: NSTrackingArea?
  private var hovered = false { didSet { needsDisplay = true } }
  override var alignmentRectInsets: NSEdgeInsets { .init() }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hover { removeTrackingArea(hover) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    addTrackingArea(area)
    hover = area
  }

  override func mouseEntered(with event: NSEvent) { hovered = true }
  override func mouseExited(with event: NSEvent) { hovered = false }

  override func draw(_ dirtyRect: NSRect) {
    if hovered || isHighlighted {
      NSColor.quaternaryLabelColor.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }

  convenience init(title: String, symbol: String) {
    self.init(frame: .zero)
    cell = SidebarActionCell(textCell: title)
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    imagePosition = .imageLeading
    isBordered = false
    alignment = .left
    font = .systemFont(ofSize: 13, weight: .medium)
    symbolConfiguration = .init(pointSize: 14, weight: .regular)
    attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor])
    bezelStyle = .accessoryBarAction
  }
}

// Keep AppKit's button drawing and accessibility while sharing the list's icon/text columns.
private final class SidebarActionCell: NSButtonCell {
  override func imageRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.minX + 8, y: rect.midY - 8, width: 16, height: 16)
  }

  override func titleRect(forBounds rect: NSRect) -> NSRect {
    var title = super.titleRect(forBounds: rect)
    title.origin.x = rect.minX + 32
    title.size.width = max(0, rect.width - 32)
    return title
  }
}
