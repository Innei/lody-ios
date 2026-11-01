#if DEBUG
import AppKit

@MainActor
final class DebugSceneCoordinator {
  static let shared = DebugSceneCoordinator()
  private var windows: [NSWindow] = []
  private(set) var current: String?

  var front: NSWindow? {
    let parent: NSWindow?
    if let key = NSApp.keyWindow, windows.contains(where: { $0 === key || $0.tabbedWindows?.contains(key) == true }) { parent = key }
    else { parent = windows.last { $0.isVisible }.map { $0.tabGroup?.selectedWindow ?? $0 } }
    var front = parent
    while let sheet = front?.attachedSheet { front = sheet }
    return front
  }

  @discardableResult
  func open(_ id: String) -> Bool {
    guard let scene = DebugSceneFactory.scene(id) else { return false }
    close()
    windows = scene.build()
    for window in windows { window.orderFront(nil) }
    windows.last?.makeKeyAndOrderFront(nil)
    current = id
    return true
  }

  func reset() {
    MacAccent.lody.apply()
    guard let current else { return }
    open(current)
  }

  func showSettings(_ page: MacSettingsPage) {
    let window = DebugSceneFactory.settingsWindow(page: page)
    windows.append(window)
    window.makeKeyAndOrderFront(nil)
  }

  private func close() {
    for window in windows { window.close() }
    windows = []
  }

  static func window(_ content: NSViewController, title: String, size: NSSize) -> NSWindow {
    let window = MacOffscreen.windowClass.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.contentViewController = content
    window.setContentSize(size)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.identifier = NSUserInterfaceItemIdentifier("catalog-scene")
    window.title = "Catalog · \(title)"
    window.center()
    return window
  }
}
#endif
