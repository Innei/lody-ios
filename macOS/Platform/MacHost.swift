import AppKit
import LodyData

@MainActor
final class MacHost: LodyHost {
  typealias Present = (NSAlert, NSWindow, @escaping () -> Void) -> Void
  private var pressure: DispatchSourceMemoryPressure?
  private let keyWindow: () -> NSWindow?
  private let present: Present
  private var alerts: [NSAlert] = []
  private var presenting = false
  private var keyObserver: NSObjectProtocol?

  init(
    keyWindow: @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow },
    present: @escaping Present = { alert, window, done in alert.beginSheetModal(for: window) { _ in done() } }
  ) {
    self.keyWindow = keyWindow
    self.present = present
    keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.presentNextAlert() }
    }
  }

  isolated deinit {
    if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
  }

  // A Mac app stays live when another app is in front.
  var isActive: Bool { true }
  var isBackground: Bool { false }

  func watchMemoryPressure() {
    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
    source.setEventHandler { [weak self, weak source] in
      guard let event = source?.data else { return }
      MainActor.assumeIsolated { self?.memoryPressure(event) }
    }
    source.resume()
    pressure = source
  }

  func memoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
    guard !event.isDisjoint(with: [.warning, .critical]) else { return }
    NotificationCenter.default.post(name: .lodyHostDidReceiveMemoryWarning, object: nil)
  }

  func open(_ url: URL) async -> Bool {
    NSWorkspace.shared.open(url)
  }

  func copyLink(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }

  func beginSendAllowance(expired: @escaping @MainActor () -> Void) -> AnyObject? {
    NSObject()
  }

  func endSendAllowance(_ token: AnyObject) {}

  func toast(_ message: String, kind: String) {
    let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.contentViewController != nil }
    MacToast.show(message, kind: kind, in: window)
  }

  func alert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alerts.append(alert)
    presentNextAlert()
  }

  private func presentNextAlert() {
    guard !presenting, !alerts.isEmpty, let window = keyWindow() else { return }
    presenting = true
    present(alerts.removeFirst(), window) { [weak self] in
      self?.presenting = false
      self?.presentNextAlert()
    }
  }

  func presentAuthorization(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }

  func dismissAuthorization() {}

  func catalogDidUpdate(_ catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {}

  func clearSharedData() {}

  func forgetDevice() {}
}
