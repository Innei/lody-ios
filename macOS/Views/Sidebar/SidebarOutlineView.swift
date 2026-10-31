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
  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point).map { _ in self }
  }

  override func draw(_ dirtyRect: NSRect) {
    if hovered || isHighlighted {
      NSColor.quaternaryLabelColor.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }

  convenience init(title: String, symbol: String) {
    self.init(frame: .zero)
    self.title = ""
    setAccessibilityLabel(title)
    isBordered = false
    font = SidebarRowLayout.font
    bezelStyle = .accessoryBarAction
    let label = NSTextField(labelWithString: title)
    label.setAccessibilityElement(false)
    SidebarRowLayout.installTitle(label, in: self)
    SidebarRowLayout.installIcon(NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()), in: self)
  }
}
