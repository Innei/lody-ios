import AppKit

@MainActor
final class MacSceneHost {
  static let shared = MacSceneHost()
  private var window: NSWindow?
  private(set) var current: String?

  @discardableResult
  func open(_ id: String) -> Bool {
    guard let scene = MacCatalog.scene(id) else { return false }
    let window = self.window ?? makeWindow()
    self.window = window
    window.contentViewController = scene.make()
    window.setContentSize(scene.size)
    window.title = "Catalog · \(scene.title)"
    window.makeKeyAndOrderFront(nil)
    current = id
    return true
  }

  func reset() {
    guard let current else { return }
    open(current)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.identifier = NSUserInterfaceItemIdentifier("catalog-scene")
    window.center()
    return window
  }
}
