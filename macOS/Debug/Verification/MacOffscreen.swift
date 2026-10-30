#if DEBUG
import AppKit
import LodyData

@MainActor
enum MacOffscreen {
  static var enabled = LodyUIVerify.offscreen
  static var windowClass: NSWindow.Type { enabled ? MacOffscreenWindow.self : NSWindow.self }
  private static let margin: CGFloat = 400

  static func frame(_ frame: NSRect, avoiding screens: [NSRect]) -> NSRect {
    guard screens.contains(where: { $0.intersects(frame) }) else { return frame }
    let union = screens.reduce(NSRect.null) { $0.union($1) }
    let x = union.maxX + margin + max(0, frame.minX - union.minX)
    return NSRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
  }
}

// AppKit pulls titled windows back until 40 pt show on a display; only this override keeps them fully off.
final class MacOffscreenWindow: NSWindow {
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    MacOffscreen.frame(frameRect, avoiding: NSScreen.screens.map(\.frame))
  }
}
#endif
