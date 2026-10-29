import AppKit
import LodyData

@MainActor
final class MacHost: LodyHost {
  private let frontmost: () -> Bool

  init(frontmost: @escaping () -> Bool = { NSApp?.isActive ?? true }) {
    self.frontmost = frontmost
  }

  // A Mac app stays live when another app is in front; only the frontmost state changes.
  var isActive: Bool { true }
  var isBackground: Bool { false }
  var isFrontmost: Bool { frontmost() }

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
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
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
