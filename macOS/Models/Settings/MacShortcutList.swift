import AppKit
import SwiftUI

enum MacShortcutList {
  struct Row: Identifiable, Equatable {
    let title: String
    let keys: String
    var id: String { title + keys }
  }

  struct Group: Identifiable, Equatable {
    let title: String
    let rows: [Row]
    var id: String { title }
  }

  private static let named: [String: String] = [
    "\u{8}": "⌫", "\u{7F}": "⌫", "\r": "↩", "\u{1B}": "⎋", "\t": "⇥", " ": "Space",
    "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→", "\u{F728}": "⌦", "\u{F705}": "F2",
  ]

  @MainActor
  static func groups(from menu: NSMenu, appName: String = ProcessInfo.processInfo.processName) -> [Group] {
    menu.items.compactMap { item in
      guard let submenu = item.submenu else { return nil }
      let rows = rows(in: submenu)
      guard !rows.isEmpty else { return nil }
      let title = item.title.isEmpty ? submenu.title : item.title
      return Group(title: title.isEmpty ? appName : title, rows: rows)
    }
  }

  @MainActor
  private static func rows(in menu: NSMenu) -> [Row] {
    menu.items.flatMap { item -> [Row] in
      if let submenu = item.submenu { return rows(in: submenu) }
      guard !item.isSeparatorItem, !item.isHidden, !item.keyEquivalent.isEmpty else { return [] }
      return [Row(title: item.title, keys: keys(item.keyEquivalent, item.keyEquivalentModifierMask))]
    }
  }

  static func keys(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
    var flags = modifiers
    if key != key.lowercased() { flags.insert(.shift) }
    let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    let prefix = symbols.filter { flags.contains($0.0) }.map(\.1).joined()
    return prefix + (named[key] ?? key.uppercased())
  }
}
