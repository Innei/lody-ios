import AppKit

@MainActor
enum MacMainMenu {
  static func make(target: LodyMacAppDelegate) -> NSMenu {
    let bar = NSMenu()
    bar.addItem(submenu(appMenu(target: target)))
    bar.addItem(submenu(fileMenu(target: target)))
    bar.addItem(submenu(editMenu()))
    bar.addItem(submenu(viewMenu()))
    let window = windowMenu()
    bar.addItem(submenu(window))
    NSApp.windowsMenu = window
    return bar
  }

  private static func submenu(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = target
    return item
  }

  private static func appMenu(target: LodyMacAppDelegate) -> NSMenu {
    let menu = NSMenu(title: "Lody")
    menu.addItem(item(String(localized: "mac.menu.about", bundle: .lodyMac), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.settings", bundle: .lodyMac), #selector(LodyMacAppDelegate.showSettings(_:)), ",", target: target))
    #if DEBUG
    menu.addItem(item("Debug", #selector(LodyMacAppDelegate.showDebug(_:)), "d", [.command, .option], target: target))
    #endif
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.hide", bundle: .lodyMac), #selector(NSApplication.hide(_:)), "h"))
    menu.addItem(item(String(localized: "mac.menu.hideOthers", bundle: .lodyMac), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
    menu.addItem(item(String(localized: "mac.menu.showAll", bundle: .lodyMac), #selector(NSApplication.unhideAllApplications(_:))))
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.quit", bundle: .lodyMac), #selector(NSApplication.terminate(_:)), "q"))
    return menu
  }

  private static func fileMenu(target: LodyMacAppDelegate) -> NSMenu {
    let menu = NSMenu(title: String(localized: "mac.menu.file", bundle: .lodyMac))
    menu.addItem(item(String(localized: "mac.menu.newSession", bundle: .lodyMac), #selector(LodyMacAppDelegate.newSessionTab(_:)), "n", target: target))
    menu.addItem(item(String(localized: "mac.menu.newTab", bundle: .lodyMac), #selector(NSResponder.newWindowForTab(_:)), "t"))
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.close", bundle: .lodyMac), #selector(NSWindow.performClose(_:)), "w"))
    return menu
  }

  private static func editMenu() -> NSMenu {
    let menu = NSMenu(title: String(localized: "mac.menu.edit", bundle: .lodyMac))
    menu.addItem(item(String(localized: "mac.menu.undo", bundle: .lodyMac), Selector(("undo:")), "z"))
    menu.addItem(item(String(localized: "mac.menu.redo", bundle: .lodyMac), Selector(("redo:")), "z", [.command, .shift]))
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.cut", bundle: .lodyMac), #selector(NSText.cut(_:)), "x"))
    menu.addItem(item(String(localized: "mac.menu.copy", bundle: .lodyMac), #selector(NSText.copy(_:)), "c"))
    menu.addItem(item(String(localized: "mac.menu.paste", bundle: .lodyMac), #selector(NSText.paste(_:)), "v"))
    menu.addItem(item(String(localized: "mac.menu.selectAll", bundle: .lodyMac), #selector(NSText.selectAll(_:)), "a"))
    return menu
  }

  private static func viewMenu() -> NSMenu {
    let menu = NSMenu(title: String(localized: "mac.menu.view", bundle: .lodyMac))
    menu.addItem(item(String(localized: "mac.menu.toggleSidebar", bundle: .lodyMac), #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
    menu.addItem(item(String(localized: "mac.menu.fullScreen", bundle: .lodyMac), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
    return menu
  }

  private static func windowMenu() -> NSMenu {
    let menu = NSMenu(title: String(localized: "mac.menu.window", bundle: .lodyMac))
    menu.addItem(item(String(localized: "mac.menu.minimize", bundle: .lodyMac), #selector(NSWindow.performMiniaturize(_:)), "m"))
    menu.addItem(item(String(localized: "mac.menu.zoom", bundle: .lodyMac), #selector(NSWindow.performZoom(_:))))
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "mac.menu.bringAllToFront", bundle: .lodyMac), #selector(NSApplication.arrangeInFront(_:))))
    return menu
  }
}
