import AppKit

@MainActor
final class MacSceneHost {
  static let shared = MacSceneHost()
  private var windows: [NSWindow] = []
  private(set) var current: String?

  @discardableResult
  func open(_ id: String) -> Bool {
    guard let scene = MacCatalog.scene(id) else { return false }
    close()
    windows = scene.build()
    for window in windows { window.orderFront(nil) }
    windows.last?.makeKeyAndOrderFront(nil)
    current = id
    return true
  }

  func reset() {
    guard let current else { return }
    open(current)
  }

  private func close() {
    for window in windows { window.close() }
    windows = []
  }

  static func window(_ content: NSViewController, title: String, size: NSSize) -> NSWindow {
    let window = NSWindow(
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
