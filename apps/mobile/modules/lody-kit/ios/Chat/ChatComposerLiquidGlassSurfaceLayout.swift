import UIKit

final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  static let sheetCornerRadius: CGFloat = 28
  // The iOS 26 keyboard has rounded top corners; material continuing behind it keeps the sheet from showing a seam there.
  static let sheetBleed: CGFloat = 40
  private let inputSurface: UIVisualEffectView
  private let pill: [NSLayoutConstraint]
  private let sheet: [NSLayoutConstraint]
  private var isFocused = false

  init(container: UIVisualEffectView, inputSurface: UIVisualEffectView) {
    self.inputSurface = inputSurface
    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = 8
    container.effect = containerEffect
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    inputSurface.effect = glass
    let host = container.contentView
    pill = [
      inputSurface.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
      inputSurface.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
      inputSurface.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8),
    ]
    sheet = [
      inputSurface.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      inputSurface.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      inputSurface.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: Self.sheetBleed),
    ]
  }

  func activate() {
    NSLayoutConstraint.activate(pill)
    applyCorners()
  }

  func update(isFocused: Bool) {
    guard self.isFocused != isFocused else { return }
    self.isFocused = isFocused
    NSLayoutConstraint.deactivate(isFocused ? pill : sheet)
    NSLayoutConstraint.activate(isFocused ? sheet : pill)
    applyCorners()
  }

  private func applyCorners() {
    if isFocused {
      let top = UICornerRadius.fixed(Self.sheetCornerRadius)
      inputSurface.cornerConfiguration = .corners(topLeftRadius: top, topRightRadius: top, bottomLeftRadius: .fixed(0), bottomRightRadius: .fixed(0))
    } else {
      inputSurface.cornerConfiguration = .capsule(maximumRadius: 24)
    }
  }
}
