import AppKit
import LodyData

@MainActor
final class MacTabBadgeView: NSImageView {
  convenience init(_ badge: MacTabBadge) {
    switch badge {
    case .approval:
      self.init(image: NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil) ?? NSImage())
      symbolConfiguration = .init(pointSize: 10, weight: .regular)
      contentTintColor = .systemOrange
      setAccessibilityIdentifier("tab-badge-approval")
    case .working:
      self.init(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage())
      symbolConfiguration = .init(pointSize: 7, weight: .bold)
      contentTintColor = .lodyAccent
      setAccessibilityIdentifier("tab-badge-working")
    }
  }
}
