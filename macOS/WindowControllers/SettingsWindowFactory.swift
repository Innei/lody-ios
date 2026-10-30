import AppKit
import SwiftUI

@MainActor
enum SettingsWindowFactory {
  static func make(model: MacSettingsModel, windowClass: NSWindow.Type = NSWindow.self) -> NSWindowController {
    let hosting = NSHostingController(rootView: MacSettingsView(model: model))
    hosting.sceneBridgingOptions = [.toolbars]
    let window = windowClass.init(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.contentViewController = hosting
    window.setContentSize(NSSize(width: 760, height: 540))
    window.contentMinSize = NSSize(width: 680, height: 440)
    window.title = String(localized: "mac.settings.title", bundle: .lodyMac)
    window.identifier = NSUserInterfaceItemIdentifier("settings")
    window.toolbarStyle = .unified
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("lody.mac.settings.window")
    track(model, window)
    return NSWindowController(window: window)
  }

  private static func track(_ model: MacSettingsModel, _ window: NSWindow) {
    withObservationTracking {
      window.title = model.shownPage.title
    } onChange: { [weak model, weak window] in
      Task { @MainActor in
        guard let model, let window else { return }
        track(model, window)
      }
    }
  }
}
