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

  override func frameOfOutlineCell(atRow row: Int) -> NSRect {
    guard let node = item(atRow: row) as? SidebarViewController.Node, node.kind == .project else { return .zero }
    var rect = super.frameOfOutlineCell(atRow: row)
    rect.origin.x = 7
    rect.size.width = 10
    return rect
  }

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
  convenience init(title: String, symbol: String) {
    self.init(frame: .zero)
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    imagePosition = .imageLeading
    isBordered = false
    alignment = .left
    font = .systemFont(ofSize: 13)
  }
}
