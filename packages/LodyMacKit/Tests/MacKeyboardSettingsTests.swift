import AppKit
import XCTest
@testable import LodyMacKit

@MainActor
final class MacShortcutListTests: XCTestCase {
  func testMenusBecomeGroupsOfRenderedShortcuts() {
    let main = NSMenu()
    let file = NSMenu(title: "File")
    file.addItem(withTitle: "New Session", action: nil, keyEquivalent: "n")
    let tab = file.addItem(withTitle: "Reopen Tab", action: nil, keyEquivalent: "t")
    tab.keyEquivalentModifierMask = [.command, .shift]
    file.addItem(.separator())
    file.addItem(withTitle: "Export…", action: nil, keyEquivalent: "")
    let view = NSMenu(title: "View")
    view.addItem(withTitle: "Zoom", action: nil, keyEquivalent: "")
    let delete = NSMenu(title: "Edit")
    let back = delete.addItem(withTitle: "Delete", action: nil, keyEquivalent: "\u{8}")
    back.keyEquivalentModifierMask = [.command]
    for submenu in [file, view, delete] {
      let item = main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "")
      main.setSubmenu(submenu, for: item)
    }
    let groups = MacShortcutList.groups(from: main)
    XCTAssertEqual(groups.map(\.title), ["File", "Edit"])
    XCTAssertEqual(groups[0].rows.map(\.title), ["New Session", "Reopen Tab"])
    XCTAssertEqual(groups[0].rows.map(\.keys), ["⌘N", "⇧⌘T"])
    XCTAssertEqual(groups[1].rows.map(\.keys), ["⌘⌫"])
  }

  func testTheAppMenuIsTitledWithTheAppName() {
    let main = NSMenu()
    let app = NSMenu(title: "")
    app.addItem(withTitle: "Settings…", action: nil, keyEquivalent: ",")
    let item = main.addItem(withTitle: "", action: nil, keyEquivalent: "")
    main.setSubmenu(app, for: item)
    XCTAssertEqual(MacShortcutList.groups(from: main, appName: "Lody").first?.title, "Lody")
  }
}
