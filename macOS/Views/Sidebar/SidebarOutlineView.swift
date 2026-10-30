import AppKit
import LodyData

final class SidebarOutlineView: NSOutlineView {
  var onReturn: (() -> Void)?

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
