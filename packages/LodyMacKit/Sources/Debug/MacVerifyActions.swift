import AppKit

// Drives controls in-process so behavior checks still run while the screen is locked and auv cannot click.
@MainActor
enum MacVerifyActions {
  private(set) static var last: [String: Any] = [:]

  static func run(_ seq: Int, _ action: MacVerifyAction, in window: NSWindow?) {
    let error = window.map { perform(action, in: $0) } ?? "no scene window"
    last = ["seq": seq, "ok": error == nil, "error": error ?? ""]
  }

  static func perform(_ action: MacVerifyAction, in window: NSWindow) -> String? {
    guard let root = window.contentView else { return "no content view" }
    let views = descendants(root).filter { !$0.isHiddenOrHasHiddenAncestor }
    switch action {
    case .click(let text):
      if let button = views.compactMap({ $0 as? NSButton }).first(where: { !($0 is NSPopUpButton) && $0.title == text && $0.isEnabled }) {
        button.performClick(nil)
        return nil
      }
      for outline in views.compactMap({ $0 as? NSOutlineView }) {
        let row = (0..<outline.numberOfRows).first { row in
          (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == text
        }
        if let row {
          outline.selectRowIndexes([row], byExtendingSelection: false)
          return nil
        }
      }
      return "no click target \(text)"
    case .choose(let current, let option):
      guard let popup = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.titleOfSelectedItem == current && $0.isEnabled }),
            popup.item(withTitle: option) != nil else { return "no popup \(current) with \(option)" }
      popup.selectItem(withTitle: option)
      popup.sendAction(popup.action, to: popup.target)
      return nil
    case .type(let field, let text):
      guard let input = views.compactMap({ $0 as? NSTextView }).first(where: {
        ($0 as? MacComposerTextView)?.placeholder == field || $0.accessibilityIdentifier() == field
      }) else { return "no input \(field)" }
      window.makeFirstResponder(input)
      input.selectAll(nil)
      input.insertText(text, replacementRange: input.selectedRange())
      return nil
    case .key:
      guard let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
        isARepeat: false, keyCode: 36
      ) else { return "no key event" }
      if !window.performKeyEquivalent(with: event) { window.firstResponder?.keyDown(with: event) }
      return nil
    }
  }

  private static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }
}
