import AppKit
import LodyData

@MainActor
final class MacPaletteWindowController: NSWindowController, NSWindowDelegate {
  let content: MacPaletteController
  var onDismiss: (() -> Void)?
  private weak var parentWindow: NSWindow?
  private weak var previousResponder: NSResponder?
  private var monitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var preferredSize = NSSize(width: 640, height: 400)
  private var dismissed = false

  init(source: MacSessionsSource, mode: MacPaletteModel.Mode, parent: NSWindow, onPick: @escaping (MacPaletteModel.Destination) -> Void) {
    parentWindow = parent
    previousResponder = parent.firstResponder
    content = MacPaletteController(state: source.read(), mode: mode)
    let panel = MacCommandPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = true
    panel.identifier = NSUserInterfaceItemIdentifier("command-palette")
    panel.setAccessibilityLabel(String(localized: "mac.palette.title", bundle: .lodyMac))
    super.init(window: panel)
    panel.delegate = self
    panel.contentViewController = content
    content.onPick = { [weak self] destination in
      guard let self, !dismissed else { return }
      dismiss(restoreFocus: false)
      onPick(destination)
    }
    content.onClose = { [weak self] in self?.dismiss() }
    content.onResize = { [weak self] size in self?.preferredSize = size; self?.place() }
    let initial = source.read()
    let scope = [initial.userId, initial.workspaceId]
    for name in source.changes {
      observe(name, object: nil) { [weak self] in
        let next = source.read()
        guard [next.userId, next.workspaceId] == scope else { self?.dismiss(); return }
        self?.content.update(next)
      }
    }
    for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
      observe(name, object: parent) { [weak self] in self?.place() }
    }
    for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
      observe(name, object: parent) { [weak self] in self?.dismiss(restoreFocus: false) }
    }
    observe(NSApplication.didResignActiveNotification, object: NSApp) { [weak self] in self?.dismiss(restoreFocus: false) }
    observe(NSWindow.didBecomeMainNotification, object: nil) { [weak self] in
      guard let self, let parentWindow else { return }
      if NSApp.mainWindow !== parentWindow { dismiss(restoreFocus: false) }
    }
    content.reload()
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  func present() {
    guard let parentWindow, let window else { return }
    place()
    parentWindow.addChildWindow(window, ordered: .above)
    window.makeKeyAndOrderFront(nil)
    content.focusSearch()
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self else { return false }
        if event.type == .keyDown, event.window === self.window,
          event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
          self.content.showActions()
          return true
        }
        if event.type != .keyDown, event.window === self.parentWindow { self.dismiss() }
        return false
      }
      return consumed ? nil : event
    }
  }

  func dismiss(restoreFocus: Bool = true) {
    let responder = previousResponder
    let parent = parentWindow
    close()
    if restoreFocus, let responder { parent?.makeFirstResponder(responder) }
  }

  override func close() {
    guard !dismissed else { return }
    dismissed = true
    cleanup()
    super.close()
    onDismiss?()
  }

  func windowWillClose(_ notification: Notification) {
    cleanup()
    if !dismissed { dismissed = true; onDismiss?() }
  }

  private func cleanup() {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    if let window { parentWindow?.removeChildWindow(window) }
  }

  private func place() {
    guard !dismissed, let parentWindow, let window else { return }
    let width = min(preferredSize.width, max(320, parentWindow.frame.width - 48))
    let height = min(preferredSize.height, max(160, parentWindow.frame.height - 80))
    let top = parentWindow.frame.maxY - min(112, parentWindow.frame.height * 0.14)
    let origin = NSPoint(x: parentWindow.frame.midX - width / 2, y: max(parentWindow.frame.minY + 20, top - height))
    window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: window.isVisible)
  }

  private func observe(_ name: Notification.Name, object: Any?, action: @escaping @MainActor () -> Void) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
      MainActor.assumeIsolated { action() }
    })
  }
}

private final class MacCommandPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
