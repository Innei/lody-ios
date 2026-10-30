import AppKit

struct MacJellyfishMotion {
  static let revealDuration: TimeInterval = 1.6
  static let leaveDuration: TimeInterval = 1
  static let cell: CGFloat = 3

  var reduceMotion: Bool

  @MainActor static var system: MacJellyfishMotion {
    MacJellyfishMotion(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }

  var leaveDuration: TimeInterval { reduceMotion ? 0 : Self.leaveDuration }

  func reveal(elapsed: TimeInterval) -> Float {
    reduceMotion ? 1 : Float(min(1, max(0, elapsed / Self.revealDuration)))
  }

  func leave(elapsed: TimeInterval?) -> Float {
    guard let elapsed else { return 0 }
    guard leaveDuration > 0 else { return 1 }
    return Float(min(1, max(0, elapsed / leaveDuration)))
  }

  static func grid(for size: NSSize) -> (columns: Int, rows: Int) {
    (max(1, Int(size.width / cell)), max(1, Int(size.height / cell)))
  }
}
