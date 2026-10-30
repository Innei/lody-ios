import AppKit
import LodyData

extension MacSessionAction {
  static let menuOrder: [MacSessionAction] = [.rename, .archive, .pin, .read]

  var keyEquivalent: String {
    switch self {
    case .rename: String(Character(UnicodeScalar(UInt16(NSF2FunctionKey))!))
    case .archive: "a"
    case .pin: "p"
    case .read: "u"
    case .delete: "\u{8}"
    }
  }

  var modifiers: NSEvent.ModifierFlags {
    switch self {
    case .rename: []
    case .archive, .pin: [.command, .option]
    case .read: [.command, .shift]
    case .delete: [.command]
    }
  }

  var defaultTitle: String {
    let key = switch self {
    case .rename: "mac.session.rename"
    case .archive: "mac.session.archive"
    case .pin: "mac.session.pin"
    case .read: "mac.session.read"
    case .delete: "mac.session.delete"
    }
    return String(localized: String.LocalizationValue(key), bundle: .lodyMac)
  }

  @MainActor
  func menuItem(_ title: String, action selector: Selector, target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
    item.keyEquivalentModifierMask = modifiers
    item.representedObject = rawValue
    item.target = target
    return item
  }
}

@MainActor
extension MacSessionPrompts {
  static func live(window: @escaping @MainActor () -> NSWindow?) -> MacSessionPrompts {
    MacSessionPrompts(
      rename: { session in
        guard let window = window() else { return nil }
        let alert = NSAlert()
        alert.messageText = text("mac.session.rename.title")
        let field = NSTextField(string: session.title)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.setAccessibilityIdentifier("session-rename-field")
        alert.accessoryView = field
        alert.addButton(withTitle: text("mac.session.rename.save"))
        alert.addButton(withTitle: text("mac.session.cancel"))
        alert.window.initialFirstResponder = field
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn ? field.stringValue : nil
      },
      confirmDelete: { session, tabs in
        guard let window = window() else { return false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: text("mac.session.delete.title"), session.title)
        var lines = [text("mac.session.delete.message")]
        if tabs > 0 { lines.append(String(format: text("mac.session.delete.tabs"), tabs)) }
        if SessionDeletion.removesWorktree(session) { lines.append(text("mac.session.delete.worktree")) }
        alert.informativeText = lines.joined(separator: "\n\n")
        let delete = alert.addButton(withTitle: text("mac.session.delete.confirm"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: text("mac.session.cancel"))
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
      },
      blocked: { session in
        guard let window = window() else { return }
        let alert = NSAlert()
        alert.messageText = String(format: text("mac.session.delete.busy"), session.title)
        alert.addButton(withTitle: text("mac.session.ok"))
        _ = await alert.beginSheetModal(for: window)
      },
      toast: { message, kind in MacToast.show(message, kind: kind, in: window()) }
    )
  }

  private static func text(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .lodyMac)
  }
}
